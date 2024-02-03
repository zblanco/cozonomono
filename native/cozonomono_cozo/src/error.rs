use rustler::{Encoder, Env, Term};
use thiserror::Error;

#[derive(Error, Debug)]
pub enum ExError {
    #[error("Cozo Error: {0}")]
    Cozo(cozo::Error),
}

// cozo::Error does not implement std::error::Error
impl From<cozo::Error> for ExError {
    fn from(error: cozo::Error) -> Self {
        ExError::Cozo(error)
    }
}

impl Encoder for ExError {
    fn encode<'b>(&self, env: Env<'b>) -> Term<'b> {
        format!("{self}").encode(env)
    }
}
