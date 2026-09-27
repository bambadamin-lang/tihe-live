use thiserror::Error;

/// Errors surfaced across the FFI boundary.
///
/// Deliberately coarse: an attacker probing the container format or the licence checker should
/// not learn *which* byte of a header failed to verify. Detail goes to the log on the device,
/// never into the error a caller sees.
#[derive(Debug, Error)]
pub enum CoreError {
    #[error("invalid container: {0}")]
    InvalidContainer(&'static str),

    #[error("signature verification failed")]
    BadSignature,

    #[error("licence is not valid for this device")]
    WrongDevice,

    #[error("licence expired")]
    LicenseExpired,

    #[error("licence not yet valid")]
    LicenseNotYetValid,

    #[error("licence revoked")]
    LicenseRevoked,

    #[error("device clock has been set backwards")]
    ClockRollback,

    #[error("key unwrap failed")]
    KeyUnwrap,

    #[error("crypto failure")]
    Crypto,

    #[error("io error: {0}")]
    Io(#[from] std::io::Error),

    #[error("encoding error")]
    Encoding,

    #[error("not found")]
    NotFound,
}

impl From<serde_cbor::Error> for CoreError {
    fn from(_: serde_cbor::Error) -> Self {
        // The CBOR error text can describe the structure being parsed. Not useful to a caller,
        // and mildly useful to someone reverse-engineering the header layout.
        CoreError::Encoding
    }
}

impl From<base64::DecodeError> for CoreError {
    fn from(_: base64::DecodeError) -> Self {
        CoreError::Encoding
    }
}

pub type Result<T> = std::result::Result<T, CoreError>;
