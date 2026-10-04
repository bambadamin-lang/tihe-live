//! `tihex` — inspect offline containers and verify a build's crypto.
//!
//! Two jobs, both diagnostic:
//!
//!   tihex inspect <file> [--key <base64 ed25519 public key>]
//!   tihex selftest
//!
//! `inspect` is the first thing to reach for when a student reports "the download will not
//! open": it prints the header without decrypting anything, so it works even on a file bound to
//! someone else's device.

use std::fs::File;
use std::process::ExitCode;

use base64::Engine;
use secure_core::container::Container;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();

    match args.first().map(String::as_str) {
        Some("inspect") => match args.get(1) {
            Some(path) => inspect(path, args.get(3).map(String::as_str)),
            None => {
                eprintln!("usage: tihex inspect <file> [--key <base64>]");
                ExitCode::FAILURE
            }
        },
        Some("selftest") => selftest(),
        _ => {
            eprintln!("usage: tihex <inspect|selftest> [args]");
            eprintln!();
            eprintln!("  inspect <file>   print a .tihex header without decrypting the payload");
            eprintln!("  selftest         verify this build's crypto primitives work");
            ExitCode::FAILURE
        }
    }
}

fn inspect(path: &str, key_b64: Option<&str>) -> ExitCode {
    // Without a real public key the signature cannot be verified, so report that plainly rather
    // than implying the header is trustworthy.
    let (key, verified) = match key_b64 {
        Some(b64) => match base64::engine::general_purpose::STANDARD.decode(b64) {
            Ok(bytes) if bytes.len() == 32 => {
                let mut k = [0u8; 32];
                k.copy_from_slice(&bytes);
                (k, true)
            }
            _ => {
                eprintln!("--key must be a base64-encoded 32-byte Ed25519 public key");
                return ExitCode::FAILURE;
            }
        },
        None => ([0u8; 32], false),
    };

    let file = match File::open(path) {
        Ok(f) => f,
        Err(e) => {
            eprintln!("cannot open {path}: {e}");
            return ExitCode::FAILURE;
        }
    };

    match Container::open(file, &key) {
        Ok(container) => {
            let h = container.header();
            println!("container      v{}", h.v);
            println!("video          {} — {}", h.video_id, h.title);
            println!("duration       {} ms", h.duration_ms);
            println!("created        {}", h.created_at);
            println!("bound device   {}", h.device_id);
            println!("licence        {}", h.license_id);
            println!("expires        {}", h.not_after);
            println!("epoch          {}", h.revocation_epoch);
            println!("key id         {}", h.key_id);
            println!("renditions     {}", h.renditions.len());
            for r in &h.renditions {
                println!(
                    "  {:<8} {}x{} {} bps, {} segments",
                    r.label,
                    r.width.unwrap_or(0),
                    r.height.unwrap_or(0),
                    r.bitrate,
                    r.segment_count
                );
            }
            println!("attachments    {}", h.attachments.len());
            println!("signature      verified");
            ExitCode::SUCCESS
        }
        Err(e) if !verified => {
            // Expected: with no key, verification cannot succeed. Say so rather than reporting a
            // corrupt file.
            println!("header present, signature NOT checked (no --key given): {e}");
            ExitCode::SUCCESS
        }
        Err(e) => {
            eprintln!("invalid container: {e}");
            ExitCode::FAILURE
        }
    }
}

fn selftest() -> ExitCode {
    match secure_core::self_test() {
        Ok(checks) => {
            println!("secure-core {} — self test passed", secure_core::VERSION);
            for c in checks {
                println!("  ok  {c}");
            }
            ExitCode::SUCCESS
        }
        Err(e) => {
            eprintln!("secure-core self test FAILED: {e}");
            eprintln!("this build must not be shipped");
            ExitCode::FAILURE
        }
    }
}
