//! Detection of the format of image files: standard formats (JPEG, PNG,
//! TIFF, BMP, GIF, WebP) and RAW formats (CR2, NEF, ARW, DNG, ORF, RAF, RW2,
//! PEF, SRW, X3F, etc.).
//!
//! Two-step strategy:
//! 1. The file extension is compared with a known table (fast, and
//!    resolves the ambiguity between classic TIFF and the many RAW formats
//!    that are themselves TIFF containers at the magic-bytes level).
//! 2. If the extension is unknown or missing, we fall back on detection
//!    by content (magic bytes via `infer`, then a RAW decoding attempt as
//!    a last resort).

use std::path::Path;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DetectedFormat {
    Standard(StandardFormat),
    Raw(String), // readable label, e.g. "RAW Canon (CR2)"
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StandardFormat {
    Jpeg,
    Png,
    Tiff,
    Bmp,
    Gif,
    WebP,
}

impl StandardFormat {
    pub fn label(&self) -> &'static str {
        match self {
            StandardFormat::Jpeg => "JPEG",
            StandardFormat::Png => "PNG",
            StandardFormat::Tiff => "TIFF",
            StandardFormat::Bmp => "BMP",
            StandardFormat::Gif => "GIF",
            StandardFormat::WebP => "WebP",
        }
    }
}

impl DetectedFormat {
    pub fn label(&self) -> String {
        match self {
            DetectedFormat::Standard(f) => f.label().to_string(),
            DetectedFormat::Raw(label) => label.clone(),
            DetectedFormat::Unknown => "Unknown".to_string(),
        }
    }

    pub fn is_raw(&self) -> bool {
        matches!(self, DetectedFormat::Raw(_))
    }
}

/// Table of known RAW extensions -> readable label.
/// Deliberately broad list: the real success of decoding depends on
/// rawloader, but the detection label depends only on the extension.
fn raw_extension_label(ext: &str) -> Option<&'static str> {
    Some(match ext {
        "cr2" => "RAW Canon (CR2)",
        "cr3" => "RAW Canon (CR3)",
        "crw" => "RAW Canon (CRW)",
        "nef" => "RAW Nikon (NEF)",
        "nrw" => "RAW Nikon (NRW)",
        "arw" => "RAW Sony (ARW)",
        "srf" => "RAW Sony (SRF)",
        "sr2" => "RAW Sony (SR2)",
        "dng" => "RAW Adobe (DNG)",
        "orf" => "RAW Olympus (ORF)",
        "raf" => "RAW Fujifilm (RAF)",
        "rw2" => "RAW Panasonic (RW2)",
        "pef" => "RAW Pentax (PEF)",
        "srw" => "RAW Samsung (SRW)",
        "x3f" => "RAW Sigma (X3F)",
        "3fr" => "RAW Hasselblad (3FR)",
        "fff" => "RAW Hasselblad (FFF)",
        "erf" => "RAW Epson (ERF)",
        "mrw" => "RAW Minolta (MRW)",
        "mos" => "RAW Leaf (MOS)",
        "dcr" => "RAW Kodak (DCR)",
        "kdc" => "RAW Kodak (KDC)",
        "k25" => "RAW Kodak (K25)",
        "iiq" => "RAW Phase One (IIQ)",
        "raw" => "Generic RAW",
        "rwl" => "RAW Leica (RWL)",
        "gpr" => "RAW GoPro (GPR)",
        _ => return None,
    })
}

fn standard_extension(ext: &str) -> Option<StandardFormat> {
    Some(match ext {
        "jpg" | "jpeg" | "jpe" | "jfif" => StandardFormat::Jpeg,
        "png" => StandardFormat::Png,
        "tif" | "tiff" => StandardFormat::Tiff,
        "bmp" => StandardFormat::Bmp,
        "gif" => StandardFormat::Gif,
        "webp" => StandardFormat::WebP,
        _ => return None,
    })
}

/// Extensions to consider when walking a folder recursively
/// (standard + RAW). Used to filter quickly without opening each
/// file.
pub fn has_known_image_extension(path: &Path) -> bool {
    match path.extension().and_then(|e| e.to_str()) {
        Some(ext) => {
            let ext = ext.to_lowercase();
            standard_extension(&ext).is_some() || raw_extension_label(&ext).is_some()
        }
        None => false,
    }
}

/// Detects the format of an image file, by extension then by content.
pub fn detect(path: &Path) -> DetectedFormat {
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        let ext = ext.to_lowercase();
        if let Some(label) = raw_extension_label(&ext) {
            return DetectedFormat::Raw(label.to_string());
        }
        if let Some(fmt) = standard_extension(&ext) {
            return DetectedFormat::Standard(fmt);
        }
    }

    // Unknown or missing extension: fall back on the content.
    if let Ok(Some(kind)) = infer::get_from_path(path) {
        let mime = kind.mime_type();
        let std_fmt = match mime {
            "image/jpeg" => Some(StandardFormat::Jpeg),
            "image/png" => Some(StandardFormat::Png),
            "image/tiff" => None, // ambiguous: may be a TIFF-based RAW
            "image/bmp" => Some(StandardFormat::Bmp),
            "image/gif" => Some(StandardFormat::Gif),
            "image/webp" => Some(StandardFormat::WebP),
            _ => None,
        };
        if let Some(fmt) = std_fmt {
            return DetectedFormat::Standard(fmt);
        }
    }

    // Last resort: try a real RAW decode. rawloader can read the internal
    // metadata (make/model) even without a reliable extension.
    if let Ok(raw) = rawloader::decode_file(path) {
        let label = format!("RAW ({} {})", raw.make.trim(), raw.model.trim());
        return DetectedFormat::Raw(label);
    }

    DetectedFormat::Unknown
}
