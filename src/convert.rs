//! Core of the conversion: loads the source image (standard formats through
//! `image`, RAW formats through the `raw` module) then encodes it to the
//! chosen target format, never cropping or resizing, and keeping the best
//! possible fidelity given the constraints of each output format (JPEG is
//! lossy by nature; PNG, TIFF, BMP and WebP (lossless mode) are truly
//! lossless).

use image::{DynamicImage, ImageBuffer, ImageOutputFormat, Rgb};
use std::fs::File;
use std::io::BufWriter;
use std::path::Path;

use crate::formats::{self, DetectedFormat};

#[derive(Debug, Clone, Copy, PartialEq, Eq, clap::ValueEnum)]
pub enum TargetFormat {
    Jpeg,
    Png,
    Tiff,
    Bmp,
    Webp,
}

impl TargetFormat {
    pub fn extension(&self) -> &'static str {
        match self {
            TargetFormat::Jpeg => "jpg",
            TargetFormat::Png => "png",
            TargetFormat::Tiff => "tiff",
            TargetFormat::Bmp => "bmp",
            TargetFormat::Webp => "webp",
        }
    }

    /// Formats that are really lossless in the strict sense.
    pub fn is_lossless(&self) -> bool {
        !matches!(self, TargetFormat::Jpeg)
    }
}

#[derive(Debug, Clone)]
pub struct ConvertOptions {
    pub target: TargetFormat,
    /// JPEG quality (1-100). Ignored for other formats.
    pub jpeg_quality: u8,
}

/// Loads the source file (RAW or standard) into an RGB DynamicImage, at
/// full resolution, without cropping.
fn load_source(path: &Path, detected: &DetectedFormat, target: TargetFormat) -> Result<DynamicImage, String> {
    match detected {
        DetectedFormat::Raw(_) => {
            // PNG/TIFF benefit from 16-bit depth; the 8-bit output formats
            // (JPEG/BMP/WebP) do not need it.
            if matches!(target, TargetFormat::Png | TargetFormat::Tiff) {
                let d = crate::raw::decode_16bit(path)?;
                let buf: ImageBuffer<Rgb<u16>, Vec<u16>> =
                    ImageBuffer::from_raw(d.width, d.height, d.rgb)
                        .ok_or_else(|| "inconsistent 16-bit RAW buffer size".to_string())?;
                Ok(DynamicImage::ImageRgb16(buf))
            } else {
                let d = crate::raw::decode_8bit(path)?;
                let buf: ImageBuffer<Rgb<u8>, Vec<u8>> =
                    ImageBuffer::from_raw(d.width, d.height, d.rgb)
                        .ok_or_else(|| "inconsistent 8-bit RAW buffer size".to_string())?;
                Ok(DynamicImage::ImageRgb8(buf))
            }
        }
        DetectedFormat::Standard(_) | DetectedFormat::Unknown => {
            // Let `image` guess/decode; this also covers the case where detection
            // by content failed but the file is in fact a readable standard
            // format.
            image::open(path).map_err(|e| format!("decoding failed: {e}"))
        }
    }
}

fn encode_target(img: &DynamicImage, output: &Path, opts: &ConvertOptions) -> Result<(), String> {
    let file = File::create(output).map_err(|e| format!("could not create the output file: {e}"))?;
    let mut w = BufWriter::new(file);

    match opts.target {
        TargetFormat::Jpeg => {
            // JPEG supports neither alpha nor 16 bits: flatten to RGB8.
            // Maximum quality by default to minimize the loss inherent to the
            // format (JPEG remains fundamentally destructive, whatever the
            // quality setting).
            let rgb = img.to_rgb8();
            rgb.write_to(&mut w, ImageOutputFormat::Jpeg(opts.jpeg_quality))
                .map_err(|e| format!("JPEG encoding failed: {e}"))
        }
        TargetFormat::Bmp => {
            if img.color().has_alpha() {
                img.to_rgba8()
                    .write_to(&mut w, ImageOutputFormat::Bmp)
            } else {
                img.to_rgb8().write_to(&mut w, ImageOutputFormat::Bmp)
            }
            .map_err(|e| format!("BMP encoding failed: {e}"))
        }
        TargetFormat::Webp => {
            // `image` encodes WebP losslessly (VP8L) by default through this
            // path. WebP in 8 bits only.
            if img.color().has_alpha() {
                img.to_rgba8()
                    .write_to(&mut w, ImageOutputFormat::WebP)
            } else {
                img.to_rgb8().write_to(&mut w, ImageOutputFormat::WebP)
            }
            .map_err(|e| format!("WebP encoding failed: {e}"))
        }
        TargetFormat::Png => {
            // PNG is intrinsically lossless whatever the compression level; the
            // original depth (8/16 bits) and alpha are kept as provided by `img`.
            img.write_to(&mut w, ImageOutputFormat::Png)
                .map_err(|e| format!("PNG encoding failed: {e}"))
        }
        TargetFormat::Tiff => {
            // Uncompressed TIFF: lossless, fast, original depth/alpha kept.
            img.write_to(&mut w, ImageOutputFormat::Tiff)
                .map_err(|e| format!("TIFF encoding failed: {e}"))
        }
    }
}

/// Converts a source file into the output folder, with the original base
/// name and the new extension. Returns the path written.
pub fn convert_one(
    input: &Path,
    output_dir: &Path,
    opts: &ConvertOptions,
    collision: crate::cli::CollisionPolicy,
) -> Result<std::path::PathBuf, String> {
    let detected = formats::detect(input);
    if let DetectedFormat::Unknown = detected {
        return Err("unrecognized source format".to_string());
    }

    let img = load_source(input, &detected, opts.target)?;

    let stem = input
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("image");
    let mut output_path = output_dir.join(format!("{stem}.{}", opts.target.extension()));

    if output_path.exists() {
        match collision {
            crate::cli::CollisionPolicy::Overwrite => {}
            crate::cli::CollisionPolicy::Skip => {
                return Err("skipped (the destination file already exists)".to_string());
            }
            crate::cli::CollisionPolicy::Rename => {
                let mut n = 1u32;
                loop {
                    let candidate = output_dir.join(format!(
                        "{stem} ({n}).{}",
                        opts.target.extension()
                    ));
                    if !candidate.exists() {
                        output_path = candidate;
                        break;
                    }
                    n += 1;
                }
            }
        }
    }

    encode_target(&img, &output_path, opts)?;
    Ok(output_path)
}
