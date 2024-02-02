use cozo::DbInstance;
use rustler::{NifStruct, ResourceArc};
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
