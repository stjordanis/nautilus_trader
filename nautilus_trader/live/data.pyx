# -------------------------------------------------------------------------------------------------
# <copyright file="data.pyx" company="Nautech Systems Pty Ltd">
#  Copyright (C) 2015-2020 Nautech Systems Pty Ltd. All rights reserved.
#  The use of this source code is governed by the license as found in the LICENSE.md file.
#  https://nautechsystems.io
# </copyright>
# -------------------------------------------------------------------------------------------------

import zmq
from cpython.datetime cimport date

from nautilus_trader.core.correctness cimport Condition
from nautilus_trader.core.cache cimport ObjectCache
from nautilus_trader.core.message cimport Response
from nautilus_trader.model.c_enums.bar_structure cimport BarStructure
from nautilus_trader.model.identifiers cimport Symbol, Venue
from nautilus_trader.model.objects cimport BarType, Instrument
from nautilus_trader.common.clock cimport LiveClock
from nautilus_trader.common.guid cimport LiveGuidFactory
from nautilus_trader.live.logger cimport LiveLogger
from nautilus_trader.common.data cimport DataClient
from nautilus_trader.network.workers cimport RequestWorker, SubscriberWorker
from nautilus_trader.serialization.base cimport DataSerializer, InstrumentSerializer, RequestSerializer, ResponseSerializer
from nautilus_trader.serialization.data cimport (  # noqa: E211
    Utf8TickSerializer,
    Utf8BarSerializer,
    BsonDataSerializer,
    BsonInstrumentSerializer)
from nautilus_trader.serialization.constants cimport *
from nautilus_trader.serialization.serializers cimport MsgPackRequestSerializer, MsgPackResponseSerializer
from nautilus_trader.network.requests cimport DataRequest
from nautilus_trader.network.responses cimport MessageRejected, QueryFailure
from nautilus_trader.network.encryption cimport EncryptionConfig
from nautilus_trader.trade.strategy cimport TradingStrategy


cdef class LiveDataClient(DataClient):
    """
    Provides a data client for live trading.
    """

    def __init__(self,
                 zmq_context not None: zmq.Context,
                 str service_name not None='NautilusData',
                 str service_address not None='localhost',
                 int tick_rep_port=55501,
                 int tick_pub_port=55502,
                 int bar_rep_port=55503,
                 int bar_pub_port=55504,
                 int inst_rep_port=55505,
                 int inst_pub_port=55506,
                 EncryptionConfig encryption not None=EncryptionConfig(),
                 RequestSerializer request_serializer not None=MsgPackRequestSerializer(),
                 ResponseSerializer response_serializer not None=MsgPackResponseSerializer(),
                 DataSerializer data_serializer not None=BsonDataSerializer(),
                 InstrumentSerializer instrument_serializer not None=BsonInstrumentSerializer(),
                 LiveClock clock not None=LiveClock(),
                 LiveGuidFactory guid_factory not None=LiveGuidFactory(),
                 LiveLogger logger not None=LiveLogger()):
        """
        Initializes a new instance of the LiveDataClient class.

        :param zmq_context: The ZMQ context.
        :param service_name: The name of the service.
        :param service_address: The data service host IP address (default=127.0.0.1).
        :param tick_rep_port: The data service port for tick responses (default=55501).
        :param tick_pub_port: The data service port for tick publications (default=55502).
        :param bar_rep_port: The data service port for bar responses (default=55503).
        :param bar_pub_port: The data service port for bar publications (default=55504).
        :param inst_rep_port: The data service port for instrument responses (default=55505).
        :param inst_pub_port: The data service port for instrument publications (default=55506).
        :param encryption: The encryption configuration.
        :param request_serializer: The request serializer for the component.
        :param response_serializer: The response serializer for the component.
        :param data_serializer: The data serializer for the component.
        :param data_serializer: The instrument serializer for the component.
        :param logger: The logger for the component.
        :raises ValueError: If the service_address is not a valid string.
        :raises ValueError: If the tick_req_port is not in range [0, 65535].
        :raises ValueError: If the tick_sub_port is not in range [0, 65535].
        :raises ValueError: If the bar_req_port is not in range [0, 65535].
        :raises ValueError: If the bar_sub_port is not in range [0, 65535].
        :raises ValueError: If the inst_req_port is not in range [0, 65535].
        :raises ValueError: If the inst_sub_port is not in range [0, 65535].
        """
        Condition.valid_string(service_address, 'service_address')
        Condition.valid_port(tick_rep_port, 'tick_rep_port')
        Condition.valid_port(tick_pub_port, 'tick_pub_port')
        Condition.valid_port(bar_rep_port, 'bar_rep_port')
        Condition.valid_port(bar_pub_port, 'bar_pub_port')
        Condition.valid_port(inst_rep_port, 'inst_rep_port')
        Condition.valid_port(inst_pub_port, 'inst_pub_port')

        super().__init__(clock, guid_factory, logger)
        self._zmq_context = zmq_context

        self._tick_req_worker = RequestWorker(
            f'{self.__class__.__name__}.TickReqWorker',
            f'{service_name}.TickProvider',
            service_address,
            tick_rep_port,
            self._zmq_context,
            encryption,
            logger)

        self._bar_req_worker = RequestWorker(
            f'{self.__class__.__name__}.BarReqWorker',
            f'{service_name}.BarProvider',
            service_address,
            bar_rep_port,
            self._zmq_context,
            encryption,
            logger)

        self._inst_req_worker = RequestWorker(
            f'{self.__class__.__name__}.InstReqWorker',
            f'{service_name}.InstrumentProvider',
            service_address,
            inst_rep_port,
            self._zmq_context,
            encryption,
            logger)

        self._tick_sub_worker = SubscriberWorker(
            f'{self.__class__.__name__}.TickSubWorker',
            f'{service_name}.TickPublisher',
            service_address,
            tick_pub_port,
            self._zmq_context,
            self._handle_tick_sub,
            encryption,
            logger)

        self._bar_sub_worker = SubscriberWorker(
            f'{self.__class__.__name__}.BarSubWorker',
            f'{service_name}.BarPublisher',
            service_address,
            bar_pub_port,
            self._zmq_context,
            self._handle_bar_sub,
            encryption,
            logger)

        self._inst_sub_worker = SubscriberWorker(
            f'{self.__class__.__name__}.InstSubWorker',
            f'{service_name}.InstrumentPublisher',
            service_address,
            inst_pub_port,
            self._zmq_context,
            self._handle_inst_sub,
            encryption,
            logger)

        self._request_serializer = request_serializer
        self._response_serializer = response_serializer
        self._data_serializer = data_serializer
        self._instrument_serializer = instrument_serializer

        self._cached_symbols = ObjectCache(Symbol, Symbol.from_string)
        self._cached_bar_types = ObjectCache(BarType, BarType.from_string)

    cpdef void connect(self) except *:
        """
        Connect to the data service.
        """
        self._tick_req_worker.connect()
        self._tick_sub_worker.connect()
        self._bar_req_worker.connect()
        self._bar_sub_worker.connect()
        self._inst_req_worker.connect()
        self._inst_sub_worker.connect()

    cpdef void disconnect(self) except *:
        """
        Disconnect from the data service.
        """
        try:
            self._tick_req_worker.disconnect()
            self._tick_sub_worker.disconnect()
            self._bar_req_worker.disconnect()
            self._bar_sub_worker.disconnect()
            self._inst_req_worker.disconnect()
            self._inst_sub_worker.disconnect()
        except zmq.ZMQError as ex:
            self._log.exception(ex)

    cpdef void reset(self) except *:
        """
        Reset the class to its initial state.
        """
        self._cached_symbols.clear()
        self._cached_bar_types.clear()
        self._reset()

    cpdef void dispose(self) except *:
        """
        Disposes of the data client.
        """
        self._tick_req_worker.dispose()
        self._tick_sub_worker.dispose()
        self._bar_req_worker.dispose()
        self._bar_sub_worker.dispose()
        self._inst_req_worker.dispose()
        self._inst_sub_worker.dispose()

    cpdef void register_strategy(self, TradingStrategy strategy) except *:
        """
        Register the given trade strategy with the data client.

        :param strategy: The strategy to register.
        """
        Condition.not_none(strategy, 'strategy')

        strategy.register_data_client(self)

        self._log.info(f"Registered strategy {strategy}.")

    cpdef void request_ticks(
            self,
            Symbol symbol,
            date from_date,
            date to_date,
            int limit,
            callback: callable) except *:
        """
        Request ticks for the given symbol and query parameters.

        :param symbol: The symbol for the request.
        :param from_date: The from date for the request.
        :param to_date: The to date for the request.
        :param limit: The limit for the number of ticks in the response (default = no limit) (>= 0).
        :param callback: The callback for the response.
        :raises ValueError: If the limit is negative (< 0).
        :raises ValueError: If the callback is not of type callable.
        """
        Condition.not_none(symbol, 'symbol')
        Condition.not_none(from_date, 'from_datetime')
        Condition.not_none(to_date, 'to_datetime')
        Condition.not_negative_int(limit, 'limit')
        Condition.callable(callback, 'callback')

        cdef dict query = {
            DATA_TYPE: "Tick[]",
            SYMBOL: symbol.value,
            FROM_DATE: str(from_date),
            TO_DATE: str(to_date),
            LIMIT: str(limit)
        }

        cdef str limit_string = '' if limit == 0 else f'(limit={limit})'
        self._log.info(f"Requesting {symbol} ticks from {from_date} to {to_date} {limit_string}...")

        cdef DataRequest request = DataRequest(query, self._guid_factory.generate(), self.time_now())
        cdef bytes request_bytes = self._request_serializer.serialize(request)
        cdef bytes response_bytes = self._tick_req_worker.send(request_bytes)
        cdef Response response = self._response_serializer.deserialize(response_bytes)

        if isinstance(response, (MessageRejected, QueryFailure)):
            self._log.error(str(response))
            return

        cdef dict data = self._data_serializer.deserialize(response.data)
        cdef dict metadata = data[METADATA]
        cdef Symbol received_symbol = self._cached_symbols.get(metadata[SYMBOL])
        assert(received_symbol == symbol)

        callback(Utf8TickSerializer.deserialize_bytes_list(received_symbol, data[DATA]))

    cpdef void request_bars(
            self,
            BarType bar_type,
            date from_date,
            date to_date,
            int limit,
            callback: callable) except *:
        """
        Request bars for the given bar type and query parameters.

        :param bar_type: The bar type for the request.
        :param from_date: The from date for the request.
        :param to_date: The to date for the request.
        :param limit: The limit for the number of ticks in the response (default = no limit) (>= 0).
        :param callback: The callback for the response.
        :raises ValueError: If the limit is negative (< 0).
        :raises ValueError: If the callback is not of type Callable.
        """
        Condition.not_none(bar_type, 'bar_type')
        Condition.not_none(from_date, 'from_date')
        Condition.not_none(to_date, 'to_date')
        Condition.not_negative_int(limit, 'limit')
        Condition.callable(callback, 'callback')

        if bar_type.specification.structure == BarStructure.TICK:
            self._bulk_build_tick_bars(bar_type, from_date, to_date, limit, callback)
            return

        cdef dict query = {
            DATA_TYPE: "Bar[]",
            SYMBOL: bar_type.symbol.value,
            SPECIFICATION: bar_type.specification.to_string(),
            FROM_DATE: str(from_date),
            TO_DATE: str(to_date),
            LIMIT: str(limit),
        }

        cdef str limit_string = '' if limit == 0 else f'(limit={limit})'
        self._log.info(f"Requesting {bar_type} bars from {from_date} to {to_date} {limit_string}...")

        cdef DataRequest request = DataRequest(query, self._guid_factory.generate(), self.time_now())
        cdef bytes request_bytes = self._request_serializer.serialize(request)
        cdef bytes response_bytes = self._bar_req_worker.send(request_bytes)
        cdef Response response = self._response_serializer.deserialize(response_bytes)

        if isinstance(response, (MessageRejected, QueryFailure)):
            self._log.error(str(response))
            return

        cdef dict data = self._data_serializer.deserialize(response.data)
        cdef dict metadata = data[METADATA]
        cdef BarType received_bar_type = self._cached_bar_types.get(metadata[SYMBOL] + '-' + metadata[SPECIFICATION])
        assert(received_bar_type == bar_type)

        callback(received_bar_type, Utf8BarSerializer.deserialize_bytes_list(data[DATA]))

    cpdef void request_instrument(self, Symbol symbol, callback: callable) except *:
        """
        Request the instrument for the given symbol.

        :param symbol: The symbol to update.
        :param callback: The callback for the response.
        :raises ValueError: If the callback is not of type callable.
        """
        Condition.not_none(symbol, 'symbol')
        Condition.callable(callback, 'callback')

        cdef dict query = {
            DATA_TYPE: "Instrument[]",
            SYMBOL: symbol.value,
        }

        self._log.info(f"Requesting instrument for {symbol} ...")

        cdef DataRequest request = DataRequest(query, self._guid_factory.generate(), self.time_now())
        cdef bytes request_bytes = self._request_serializer.serialize(request)
        cdef bytes response_bytes = self._inst_req_worker.send(request_bytes)
        cdef Response response = self._response_serializer.deserialize(response_bytes)

        if isinstance(response, (MessageRejected, QueryFailure)):
            self._log.error(str(response))
            return

        cdef dict data = self._data_serializer.deserialize(response.data)
        cdef Instrument instrument = self._instrument_serializer.deserialize(data[DATA][0])
        assert(instrument.symbol == symbol)

        callback(instrument)

    cpdef void request_instruments(self, Venue venue, callback: callable) except *:
        """
        Request all instrument for given venue.
        
        :param venue: The venue for the request.
        :param callback: The callback for the response.
        :raises ValueError: If the callback is not of type callable.
        """
        Condition.callable(callback, 'callback')

        cdef dict query = {
            DATA_TYPE: "Instrument[]",
            VENUE: venue.value,
        }

        self._log.info(f"Requesting all instruments for {venue} ...")

        cdef DataRequest request = DataRequest(query, self._guid_factory.generate(), self.time_now())
        cdef bytes request_bytes = self._request_serializer.serialize(request)
        cdef bytes response_bytes = self._inst_req_worker.send(request_bytes)
        cdef Response response = self._response_serializer.deserialize(response_bytes)

        if isinstance(response, (MessageRejected, QueryFailure)):
            self._log.error(str(response))
            return

        cdef dict data = self._data_serializer.deserialize(response.data)
        cdef list instruments = [self._instrument_serializer.deserialize(inst) for inst in data[DATA]]
        callback(instruments)

    cpdef void update_instruments(self, Venue venue) except *:
        """
        Update all instruments for the data clients venue.
        """
        self.request_instruments(venue, self._handle_instruments_py)

    cpdef void _handle_instruments_py(self, list instruments) except *:
        # Method provides a Python wrapper for the callback
        # Handle all instruments individually
        for instrument in instruments:
            self._handle_instrument(instrument)

    cpdef void subscribe_ticks(self, Symbol symbol, handler: callable) except *:
        """
        Subscribe to live tick data for the given symbol and handler.

        :param symbol: The tick symbol to subscribe to.
        :param handler: The callable handler for subscription (if None will just call print).
        :raises ValueError: If the handler is not of type callable.
        """
        Condition.not_none(symbol, 'symbol')
        Condition.callable(handler, 'handler')

        self._add_tick_handler(symbol, handler)
        self._tick_sub_worker.subscribe(symbol.to_string())

    cpdef void subscribe_bars(self, BarType bar_type, handler: callable) except *:
        """
        Subscribe to live bar data for the given bar type and handler.

        :param bar_type: The bar type to subscribe to.
        :param handler: The callable handler for subscription.
        :raises ValueError: If the handler is not of type Callable.
        """
        Condition.not_none(bar_type, 'bar_type')
        Condition.callable(handler, 'handler')

        if bar_type.specification.structure == BarStructure.TICK:
            self._self_generate_bars(bar_type, handler)
        else:
            self._add_bar_handler(bar_type, handler)
            self._bar_sub_worker.subscribe(bar_type.to_string())

    cpdef void subscribe_instrument(self, Symbol symbol, handler: callable) except *:
        """
        Subscribe to live instrument data updates for the given symbol and handler.

        :param symbol: The instrument symbol to subscribe to.
        :param handler: The callable handler for subscription.
        :raises ValueError: If the handler is not of type Callable.
        """
        Condition.not_none(symbol, 'symbol')
        Condition.callable(handler, 'handler')

        self._add_instrument_handler(symbol, handler)
        self._inst_sub_worker.subscribe(symbol.value)

    cpdef void unsubscribe_ticks(self, Symbol symbol, handler: callable) except *:
        """
        Unsubscribe from live tick data for the given symbol and handler.

        :param symbol: The tick symbol to unsubscribe from.
        :param handler: The callable handler which was subscribed.
        :raises ValueError: If the handler is not of type Callable.
        """
        Condition.not_none(symbol, 'symbol')
        Condition.callable(handler, 'handler')

        self._tick_sub_worker.unsubscribe(symbol.to_string())
        self._remove_tick_handler(symbol, handler)

    cpdef void unsubscribe_bars(self, BarType bar_type, handler: callable) except *:
        """
        Unsubscribe from live bar data for the given symbol and handler.

        :param bar_type: The bar type to unsubscribe from.
        :param handler: The callable handler which was subscribed.
        :raises ValueError: If the handler is not of type Callable.
        """
        Condition.not_none(bar_type, 'bar_type')
        Condition.callable(handler, 'handler')

        self._bar_sub_worker.unsubscribe(bar_type.to_string())
        self._remove_bar_handler(bar_type, handler)

    cpdef void unsubscribe_instrument(self, Symbol symbol, handler: callable) except *:
        """
        Unsubscribe from live instrument data updates for the given symbol and handler.

        :param symbol: The instrument symbol to unsubscribe from.
        :param handler: The callable handler which was subscribed.
        :raises ValueError: If the handler is not of type Callable.
        """
        Condition.not_none(symbol, 'symbol')
        Condition.callable(handler, 'handler')

        self._inst_sub_worker.unsubscribe(symbol.value)
        self._remove_instrument_handler(symbol, handler)

    cpdef void _handle_tick_sub(self, str topic, bytes message) except *:
        # Handle the given tick message published for the given topic
        self._handle_tick(Utf8TickSerializer.deserialize(self._cached_symbols.get(topic), message))

    cpdef void _handle_bar_sub(self, str topic, bytes message) except *:
        # Handle the given bar message published for the given topic
        self._handle_bar(self._cached_bar_types.get(topic), Utf8BarSerializer.deserialize(message))

    cpdef void _handle_inst_sub(self, str topic, bytes message) except *:
        # Handle the given instrument message published for the given topic
        self._handle_instrument(self._instrument_serializer.deserialize(message))
