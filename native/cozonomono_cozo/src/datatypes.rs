use cozo::{DataValue, DbInstance, NamedRows};
use rustler::{Decoder, Encoder, Env, NifResult, NifStruct, ResourceArc, Term};
use std::ops::Deref;

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

        // Encode rows by manually handling DataValueWrapper
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
            Some(boxed_next) => ExNamedRows((**boxed_next).clone()).encode(env), // Recursively encode next if it exists
            None => rustler::types::atom::nil().encode(env), // Encode as nil if there is no next
        };

        // Construct a map or tuple to represent `NamedRows` in Erlang terms
        // This is an example, adjust according to your needs
        let map = rustler::Term::map_new(env)
            .map_put("headers".encode(env), headers)
            .expect("Failed to encode headers")
            .map_put("rows".encode(env), rows_term)
            .expect("Failed to encode rows")
            .map_put("next".encode(env), next)
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
            DataValue::Null => "nil".encode(env),
            DataValue::Bool(value) => value.encode(env),
            DataValue::Num(number) => match number {
                cozo::Num::Int(i) => i.encode(env),
                cozo::Num::Float(f) => f.encode(env),
            },
            DataValue::Str(str) => str.as_str().encode(env),
            DataValue::Bytes(bytes) => bytes.encode(env),
            DataValue::Uuid(cozo::UuidWrapper(uuid)) => uuid.to_string().encode(env),
            DataValue::Regex(cozo::RegexWrapper(regex)) => regex.to_string().encode(env),
            // This is recursive
            DataValue::List(list) => list
                .iter()
                .map(|data_value| ExDataValue(data_value.clone()))
                .collect::<Vec<ExDataValue>>()
                .encode(env),
            DataValue::Vec(vec) => match vec {
                cozo::Vector::F32(f32_array) => f32_array.clone().into_raw_vec().encode(env),
                cozo::Vector::F64(f64_array) => f64_array.clone().into_raw_vec().encode(env),
            },
            DataValue::Json(cozo::JsonData(json)) => json.to_string().encode(env),
            // Encode undefined values as nils
            _ => "nil".encode(env),
        }
    }
}

impl<'a> Decoder<'a> for ExDataValue {
    fn decode(term: Term<'a>) -> NifResult<Self> {
        match term.get_type() {
            // Match against the term type and decode accordingly
            rustler::TermType::Atom => {
                if term.atom_to_string()?.to_lowercase() == "nil" {
                    Ok(ExDataValue(DataValue::Null))
                } else {
                    Err(rustler::Error::Atom("unexpected_atom"))
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
            _ => {
                // Directly attempt to decode known types, fallback to complex type handling
                let decoded = if let Ok(value) = term.decode::<bool>() {
                    ExDataValue(DataValue::Bool(value))
                } else if let Ok(value) = term.decode::<i64>() {
                    ExDataValue(DataValue::Num(cozo::Num::Int(value)))
                } else if let Ok(value) = term.decode::<f64>() {
                    ExDataValue(DataValue::Num(cozo::Num::Float(value)))
                } else if let Ok(value) = term.decode::<String>() {
                    // Additional logic needed here for Uuid, Regex, Json
                    ExDataValue(DataValue::Str(value.into()))
                } else {
                    // Handle other complex types like Bytes, Vec, Uuid, Regex, and Json here
                    return Err(rustler::Error::Atom("unsupported_type"));
                };
                Ok(decoded)
            }
        }
    }
}
