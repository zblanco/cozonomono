use cozo::{DataValue, DbInstance, NamedRows};
use rustler::{Encoder, Env, NifStruct, ResourceArc, Term};
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
