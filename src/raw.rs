//! Decoding of RAW files into a full-resolution RGB image, without
//! cropping or resizing.
//!
//! `imagepipe` (based on `rawloader`) applies the standard pipeline
//! (demosaicing, white balance as recorded by the camera, color
//! conversion, gamma) without ever cropping or reducing the resolution
//! as long as `maxwidth`/`maxheight` stay at 0 and no crop operation is
//! added — which this module guarantees by using the default pipeline
//! without modifying it.
//!
//! Decoding order: `rawloader`/`imagepipe` first; if the file cannot be
//! decoded (typically a camera missing from the `rawloader` database),
//! fall back to LibRaw (`libraw.rs`); if LibRaw fails too, the combined
//! error is reported and the batch goes on with the next file.

use std::path::Path;

#[derive(Debug)]
pub struct DecodedRaw8 {
    pub width: u32,
    pub height: u32,
    pub rgb: Vec<u8>,
}

#[derive(Debug)]
pub struct DecodedRaw16 {
    pub width: u32,
    pub height: u32,
    pub rgb: Vec<u16>,
}

fn new_pipeline(path: &Path) -> Result<imagepipe::Pipeline, String> {
    let mut pipeline = imagepipe::Pipeline::new_from_file(path).map_err(|e| {
        // imagepipe hides the real cause: it tries rawloader, then
        // image::open, and returns a generic message if both fail.
        // So we call rawloader again to bring up its real error
        // (unsupported camera, unhandled compression, etc.).
        match rawloader::decode_file(path) {
            Err(raw_err) => format!("cannot open RAW file: {raw_err}"),
            Ok(_) => format!("cannot open RAW file: {e}"),
        }
    })?;
    // Full resolution, no limit -> no resizing.
    pipeline.globals.settings.maxwidth = 0;
    pipeline.globals.settings.maxheight = 0;
    // pipeline.ops.rotatecrop stays at its default value (no-op): no
    // crop added beyond the active area of the sensor handled by
    // rawloader/imagepipe itself (identical to what the camera
    // would produce).
    Ok(pipeline)
}

/// Runs a decoder, turning an internal panic (corrupted file, library
/// bug) into an error, so that the batch goes on.
fn guarded<T>(name: &str, f: impl FnOnce() -> Result<T, String>) -> Result<T, String> {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)) {
        Ok(r) => r,
        Err(_) => Err(format!("{name}: internal decoder error (corrupted file?)")),
    }
}

/// Combines the error of the main decoder and that of the LibRaw fallback.
fn combined(primary: String, fallback: String) -> String {
    // rawloader messages contain line breaks: we flatten them so that the
    // error stays readable on a single line of the log.
    let flat = |s: String| s.split_whitespace().collect::<Vec<_>>().join(" ");
    format!("{} ; LibRaw fallback: {}", flat(primary), flat(fallback))
}

/// Tries `primary`; if it fails, tries `fallback`; if both fail, reports
/// both errors (the batch goes on with the next file; the caller displays
/// the error).
fn with_fallback<T>(
    primary: impl FnOnce() -> Result<T, String>,
    fallback: impl FnOnce() -> Result<T, String>,
) -> Result<T, String> {
    match primary() {
        Ok(v) => Ok(v),
        Err(p) => fallback().map_err(|f| combined(p, f)),
    }
}

/// Decodes a RAW file into RGB at 8 bits per channel, full resolution.
/// Suited to 8-bit output formats (JPEG, BMP, WebP).
pub fn decode_8bit(path: &Path) -> Result<DecodedRaw8, String> {
    with_fallback(
        || guarded("rawloader", || decode_8bit_rawloader(path)),
        || guarded("LibRaw", || crate::libraw::decode_8bit(path)),
    )
}

/// Decodes a RAW file into RGB at 16 bits per channel, full resolution.
/// Suited to lossless output formats with extended depth (TIFF, PNG).
pub fn decode_16bit(path: &Path) -> Result<DecodedRaw16, String> {
    with_fallback(
        || guarded("rawloader", || decode_16bit_rawloader(path)),
        || guarded("LibRaw", || crate::libraw::decode_16bit(path)),
    )
}

fn decode_8bit_rawloader(path: &Path) -> Result<DecodedRaw8, String> {
    let mut pipeline = new_pipeline(path)?;
    let img = pipeline
        .output_8bit(None)
        .map_err(|e| format!("RAW decoding failed: {e}"))?;
    Ok(DecodedRaw8 {
        width: img.width as u32,
        height: img.height as u32,
        rgb: img.data,
    })
}

fn decode_16bit_rawloader(path: &Path) -> Result<DecodedRaw16, String> {
    let mut pipeline = new_pipeline(path)?;
    let img = pipeline
        .output_16bit(None)
        .map_err(|e| format!("RAW decoding failed: {e}"))?;
    Ok(DecodedRaw16 {
        width: img.width as u32,
        height: img.height as u32,
        rgb: img.data,
    })
}

/// Test only: simulates a failing main decoder (unknown camera) to check
/// that the LibRaw fallback does take over.
#[cfg(test)]
pub fn decode_with_fallback_for_tests(path: &Path) -> Result<DecodedRaw8, String> {
    with_fallback(
        || Err("Couldn't find camera \"FAKE\" \"CAM\" mode \"\"".to_string()),
        || guarded("LibRaw", || crate::libraw::decode_8bit(path)),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn primary_ok_fallback_not_called() {
        let r: Result<u8, String> =
            with_fallback(|| Ok(1), || panic!("the fallback must not be called"));
        assert_eq!(r, Ok(1));
    }

    #[test]
    fn primary_fails_fallback_used() {
        let r: Result<u8, String> = with_fallback(|| Err("unknown camera".into()), || Ok(2));
        assert_eq!(r, Ok(2));
    }

    #[test]
    fn both_fail_errors_are_combined() {
        let r: Result<u8, String> =
            with_fallback(|| Err("error A".into()), || Err("error B".into()));
        let msg = r.unwrap_err();
        assert!(msg.contains("error A") && msg.contains("error B"), "{msg}");
    }

    #[test]
    fn panic_becomes_an_error() {
        let r: Result<u8, String> = guarded("test", || panic!("boom"));
        assert!(r.unwrap_err().contains("internal decoder error"));
    }

    #[test]
    fn garbage_file_reports_both_decoders_and_does_not_crash() {
        let dir = std::env::temp_dir().join(format!("cie-raw-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let f = dir.join("garbage.arw");
        std::fs::write(&f, b"this is not a RAW file").unwrap();
        let msg = decode_8bit(&f).unwrap_err();
        assert!(msg.contains("LibRaw fallback"), "{msg}");
        let msg16 = decode_16bit(&f).unwrap_err();
        assert!(msg16.contains("LibRaw fallback"), "{msg16}");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
