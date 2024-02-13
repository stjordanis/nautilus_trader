// -------------------------------------------------------------------------------------------------
//  Copyright (C) 2015-2024 Nautech Systems Pty Ltd. All rights reserved.
//  https://nautechsystems.io
//
//  Licensed under the GNU Lesser General Public License Version 3.0 (the "License");
//  You may not use this file except in compliance with the License.
//  You may obtain a copy of the License at https://www.gnu.org/licenses/lgpl-3.0.en.html
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
// -------------------------------------------------------------------------------------------------

// use std::{
//     collections::{hash_map::DefaultHasher, HashMap},
//     hash::{Hash, Hasher},
// };

use nautilus_core::time::UnixNanos;
use pyo3::prelude::*;

use crate::{
    data::{delta::OrderBookDelta, deltas::OrderBookDeltas},
    identifiers::instrument_id::InstrumentId,
    python::PY_MODULE_MODEL,
};

#[pymethods]
impl OrderBookDeltas {
    #[new]
    fn py_new(instrument_id: InstrumentId, deltas: Vec<OrderBookDelta>) -> Self {
        Self::new(instrument_id, deltas)
    }

    // TODO: Implement
    // fn __richcmp__(&self, other: &Self, op: CompareOp, py: Python<'_>) -> Py<PyAny> {
    //     match op {
    //         CompareOp::Eq => self.eq(other).into_py(py),
    //         CompareOp::Ne => self.ne(other).into_py(py),
    //         _ => py.NotImplemented(),
    //     }
    // }

    // TODO: Implement
    // fn __hash__(&self) -> isize {
    //     let mut h = DefaultHasher::new();
    //     self.hash(&mut h);
    //     h.finish() as isize
    // }

    fn __str__(&self) -> String {
        self.to_string()
    }

    fn __repr__(&self) -> String {
        format!("{self:?}")
    }

    #[getter]
    #[pyo3(name = "instrument_id")]
    fn py_instrument_id(&self) -> InstrumentId {
        self.instrument_id
    }

    #[getter]
    #[pyo3(name = "deltas")]
    fn py_deltas(&self) -> Vec<OrderBookDelta> {
        // `OrderBookDelta` is `Copy`
        self.deltas.clone()
    }

    #[getter]
    #[pyo3(name = "flags")]
    fn py_flags(&self) -> u8 {
        self.flags
    }

    #[getter]
    #[pyo3(name = "sequence")]
    fn py_sequence(&self) -> u64 {
        self.sequence
    }

    #[getter]
    #[pyo3(name = "ts_event")]
    fn py_ts_event(&self) -> UnixNanos {
        self.ts_event
    }

    #[getter]
    #[pyo3(name = "ts_init")]
    fn py_ts_init(&self) -> UnixNanos {
        self.ts_init
    }

    #[staticmethod]
    #[pyo3(name = "fully_qualified_name")]
    fn py_fully_qualified_name() -> String {
        format!("{}:{}", PY_MODULE_MODEL, stringify!(OrderBookDeltas))
    }

    // /// Creates a `PyCapsule` containing a raw pointer to a `Data::Delta` object.
    // ///
    // /// This function takes the current object (assumed to be of a type that can be represented as
    // /// `Data::Delta`), and encapsulates a raw pointer to it within a `PyCapsule`.
    // ///
    // /// # Safety
    // ///
    // /// This function is safe as long as the following conditions are met:
    // /// - The `Data::Delta` object pointed to by the capsule must remain valid for the lifetime of the capsule.
    // /// - The consumer of the capsule must ensure proper handling to avoid dereferencing a dangling pointer.
    // ///
    // /// # Panics
    // ///
    // /// The function will panic if the `PyCapsule` creation fails, which can occur if the
    // /// `Data::Delta` object cannot be converted into a raw pointer.
    // ///
    // #[pyo3(name = "as_pycapsule")]
    // fn py_as_pycapsule(&self, py: Python<'_>) -> PyObject {
    //     data_to_pycapsule(py, Data::Delta(*self))
    // }

    // TODO: Implement `Serializable` and the other methods can be added
}