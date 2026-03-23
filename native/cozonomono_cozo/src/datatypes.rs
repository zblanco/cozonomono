use cozo::{DataValue, DbInstance, NamedRows};
use rustler::types::map::MapIterator;
use rustler::{Decoder, Encoder, Env, NifResult, NifStruct, ResourceArc, Term};
use std::ops::Deref;

mod atoms {
    rustler::atoms! {
        nil,
        ok,
        error,
        validity,
        json,
        named_rows_struct = "Elixir.Cozonomono.NamedRows",
        __struct__,
        headers,
        rows,
        next,
    }
}

pub struct ExDbInstanceRef(pub DbInstance);

#[derive(NifStruct)]
#[module = "Cozonomono.Instance"]
pub struct ExDbInstance {
    pub resource: ResourceArc<ExDbInstanceRef>,
    pub engine: String,
    pub path: String,
}

impl ExDbInstanceRef {
    pub fn new(instance: DbInstance) -> Self {
        Self(instance)
    }
}

impl ExDbInstance {
    pub fn new(instance: DbInstance, engine: String, path: String) -> Self {
        Self {
            resource: ResourceArc::new(ExDbInstanceRef::new(instance)),
            engine,
            path,
        }
    }
}

impl Deref for ExDbInstance {
    type Target = DbInstance;

    fn deref(&self) -> &Self::Target {
        &self.resource.0
    }
}

pub struct ExNamedRows(pub NamedRows);

impl Deref for ExNamedRows {
    type Target = NamedRows;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl Encoder for ExNamedRows {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        let headers = self.headers.encode(env);

        let rows: Vec<Term<'a>> = self
            .0
            .rows
            .iter()
            .map(|row| {
                row.iter()
                    .map(|data_value| ExDataValue(data_value.clone()).encode(env))
                    .collect::<Vec<Term<'a>>>()
                    .encode(env)
            })
            .collect();

        let rows_term = rows.encode(env);

        let next = match &self.0.next {
            Some(boxed_next) => ExNamedRows((**boxed_next).clone()).encode(env),
            None => atoms::nil().encode(env),
        };

        let map = rustler::Term::map_new(env)
            .map_put(atoms::__struct__().encode(env), atoms::named_rows_struct().encode(env))
            .expect("Failed to encode __struct__")
            .map_put(atoms::headers().encode(env), headers)
            .expect("Failed to encode headers")
            .map_put(atoms::rows().encode(env), rows_term)
            .expect("Failed to encode rows")
            .map_put(atoms::next().encode(env), next)
            .expect("Failed to encode next");

        map
    }
}

pub struct ExDataValue(pub DataValue);

impl Deref for ExDataValue {
    type Target = DataValue;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl Encoder for ExDataValue {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        match &self.0 {
            DataValue::Null => atoms::nil().encode(env),
            DataValue::Bool(value) => value.encode(env),
            DataValue::Num(number) => match number {
                cozo::Num::Int(i) => i.encode(env),
                cozo::Num::Float(f) => f.encode(env),
            },
            DataValue::Str(str) => str.as_str().encode(env),
            DataValue::Bytes(bytes) => bytes.as_slice().encode(env),
            DataValue::Uuid(cozo::UuidWrapper(uuid)) => uuid.to_string().encode(env),
            DataValue::Regex(cozo::RegexWrapper(regex)) => regex.to_string().encode(env),
            DataValue::List(list) => list
                .iter()
                .map(|data_value| ExDataValue(data_value.clone()))
                .collect::<Vec<ExDataValue>>()
                .encode(env),
            DataValue::Set(set) => set
                .iter()
                .map(|data_value| ExDataValue(data_value.clone()))
                .collect::<Vec<ExDataValue>>()
                .encode(env),
            DataValue::Vec(vec) => match vec {
                cozo::Vector::F32(f32_array) => f32_array.clone().into_raw_vec().encode(env),
                cozo::Vector::F64(f64_array) => f64_array.clone().into_raw_vec().encode(env),
            },
            DataValue::Json(cozo::JsonData(json)) => {
                encode_json_value(json, env)
            }
            DataValue::Validity(validity) => {
                let timestamp = validity.timestamp.0 .0;
                let is_assert = validity.is_assert.0;
                (atoms::validity(), timestamp, is_assert).encode(env)
            }
            DataValue::Bot => atoms::nil().encode(env),
        }
    }
}

/// Encode a serde_json::Value as a native Elixir term (maps, lists, strings, numbers, booleans, nil).
fn encode_json_value<'a>(value: &serde_json::Value, env: Env<'a>) -> Term<'a> {
    match value {
        serde_json::Value::Null => atoms::nil().encode(env),
        serde_json::Value::Bool(b) => b.encode(env),
        serde_json::Value::Number(n) => {
            if let Some(i) = n.as_i64() {
                i.encode(env)
            } else if let Some(f) = n.as_f64() {
                f.encode(env)
            } else {
                atoms::nil().encode(env)
            }
        }
        serde_json::Value::String(s) => s.as_str().encode(env),
        serde_json::Value::Array(arr) => arr
            .iter()
            .map(|v| encode_json_value(v, env))
            .collect::<Vec<Term<'a>>>()
            .encode(env),
        serde_json::Value::Object(map) => {
            let mut term_map = Term::map_new(env);
            for (k, v) in map {
                term_map = term_map
                    .map_put(k.as_str().encode(env), encode_json_value(v, env))
                    .expect("Failed to encode JSON map entry");
            }
            term_map
        }
    }
}

impl<'a> Decoder<'a> for ExDataValue {
    fn decode(term: Term<'a>) -> NifResult<Self> {
        match term.get_type() {
            rustler::TermType::Atom => {
                let atom_str = term.atom_to_string()?;
                match atom_str.as_str() {
                    "nil" => Ok(ExDataValue(DataValue::Null)),
                    "true" => Ok(ExDataValue(DataValue::Bool(true))),
                    "false" => Ok(ExDataValue(DataValue::Bool(false))),
                    _ => Err(rustler::Error::Atom("unexpected_atom")),
                }
            }
            rustler::TermType::List => {
                let list = term.decode::<Vec<Term>>()?;
                let decoded_list = list
                    .iter()
                    .map(|item| ExDataValue::decode(*item))
                    .collect::<Result<Vec<_>, _>>()?;
                Ok(ExDataValue(DataValue::List(
                    decoded_list.into_iter().map(|ev| ev.0).collect(),
                )))
            }
            rustler::TermType::Map => {
                // Check if this is a tagged tuple-style map or a plain JSON-like map.
                // Decode Elixir maps as DataValue::Json via serde_json::Value::Object.
                let json_value = decode_map_to_json(term)?;
                Ok(ExDataValue(DataValue::Json(cozo::JsonData(json_value))))
            }
            rustler::TermType::Binary => {
                // Try to decode as UTF-8 string first.
                // If it's a valid string, check if it's a UUID format.
                if let Ok(s) = term.decode::<String>() {
                    if let Ok(uuid) = uuid::Uuid::parse_str(&s) {
                        Ok(ExDataValue(DataValue::Uuid(cozo::UuidWrapper(uuid))))
                    } else {
                        Ok(ExDataValue(DataValue::Str(s.into())))
                    }
                } else {
                    // Not valid UTF-8 — treat as raw bytes
                    let bytes = term.decode::<Vec<u8>>()?;
                    Ok(ExDataValue(DataValue::Bytes(bytes)))
                }
            }
            _ => {
                // Try numeric types
                if let Ok(value) = term.decode::<bool>() {
                    Ok(ExDataValue(DataValue::Bool(value)))
                } else if let Ok(value) = term.decode::<i64>() {
                    Ok(ExDataValue(DataValue::Num(cozo::Num::Int(value))))
                } else if let Ok(value) = term.decode::<f64>() {
                    Ok(ExDataValue(DataValue::Num(cozo::Num::Float(value))))
                } else {
                    Err(rustler::Error::Atom("unsupported_type"))
                }
            }
        }
    }
}

/// Recursively decode an Elixir map term into a serde_json::Value::Object.
fn decode_map_to_json(term: Term<'_>) -> NifResult<serde_json::Value> {
    let iter = MapIterator::new(term).ok_or(rustler::Error::Atom("invalid_map"))?;

    let mut map = serde_json::Map::new();
    for (key, value) in iter {
        let key_str = key
            .decode::<String>()
            .map_err(|_| rustler::Error::Atom("json_keys_must_be_strings"))?;
        let json_value = decode_term_to_json(value)?;
        map.insert(key_str, json_value);
    }
    Ok(serde_json::Value::Object(map))
}

/// Recursively decode any Elixir term into a serde_json::Value.
fn decode_term_to_json(term: Term<'_>) -> NifResult<serde_json::Value> {
    match term.get_type() {
        rustler::TermType::Atom => {
            let atom_str = term.atom_to_string()?;
            match atom_str.as_str() {
                "nil" => Ok(serde_json::Value::Null),
                "true" => Ok(serde_json::Value::Bool(true)),
                "false" => Ok(serde_json::Value::Bool(false)),
                _ => Ok(serde_json::Value::String(atom_str)),
            }
        }
        rustler::TermType::List => {
            let list = term.decode::<Vec<Term>>()?;
            let arr = list
                .iter()
                .map(|item| decode_term_to_json(*item))
                .collect::<Result<Vec<_>, _>>()?;
            Ok(serde_json::Value::Array(arr))
        }
        rustler::TermType::Map => decode_map_to_json(term),
        rustler::TermType::Binary => {
            let s = term
                .decode::<String>()
                .map_err(|_| rustler::Error::Atom("json_string_must_be_utf8"))?;
            Ok(serde_json::Value::String(s))
        }
        _ => {
            if let Ok(value) = term.decode::<bool>() {
                Ok(serde_json::Value::Bool(value))
            } else if let Ok(value) = term.decode::<i64>() {
                Ok(serde_json::Value::Number(value.into()))
            } else if let Ok(value) = term.decode::<f64>() {
                match serde_json::Number::from_f64(value) {
                    Some(n) => Ok(serde_json::Value::Number(n)),
                    None => Ok(serde_json::Value::Null), // NaN/Infinity can't be JSON
                }
            } else {
                Err(rustler::Error::Atom("unsupported_json_type"))
            }
        }
    }
}
