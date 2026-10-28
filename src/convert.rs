//! Cœur de la conversion : charge l'image source (formats standards via
//! `image`, formats RAW via le module `raw`) puis l'encode vers le format
//! cible choisi, sans jamais recadrer ni redimensionner, et en conservant
//! la meilleure fidélité possible compte tenu des contraintes propres à
//! chaque format de sortie (JPEG reste par nature un format avec perte ;
//! PNG, TIFF, BMP et WebP (mode sans perte) sont eux authentiquement
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

    /// Formats réellement sans perte au sens strict.
    pub fn is_lossless(&self) -> bool {
        !matches!(self, TargetFormat::Jpeg)
    }
}

#[derive(Debug, Clone)]
pub struct ConvertOptions {
    pub target: TargetFormat,
    /// Qualité JPEG (1-100). Ignoré pour les autres formats.
    pub jpeg_quality: u8,
}

/// Charge le fichier source (RAW ou standard) en une DynamicImage RGB,
/// à pleine résolution, sans recadrage.
fn load_source(path: &Path, detected: &DetectedFormat, target: TargetFormat) -> Result<DynamicImage, String> {
    match detected {
        DetectedFormat::Raw(_) => {
            // PNG/TIFF profitent de la profondeur 16 bits ; les formats de
            // sortie 8 bits (JPEG/BMP/WebP) n'en ont pas besoin.
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
            // On laisse `image` deviner/décoder ; ça couvre aussi le cas où
            // la détection par contenu avait échoué mais où le fichier est
            // en fait un format standard lisible.
            image::open(path).map_err(|e| format!("decoding failed: {e}"))
        }
    }
}

fn encode_target(img: &DynamicImage, output: &Path, opts: &ConvertOptions) -> Result<(), String> {
    let file = File::create(output).map_err(|e| format!("could not create the output file: {e}"))?;
    let mut w = BufWriter::new(file);

    match opts.target {
        TargetFormat::Jpeg => {
            // JPEG ne supporte ni l'alpha ni 16 bits : on aplatit en RGB8.
            // Qualité maximale par défaut pour minimiser la perte propre
            // au format (JPEG reste fondamentalement destructif, quel que
            // soit le réglage de qualité).
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
            // `image` encode en WebP sans perte (VP8L) par défaut via ce
            // chemin. WebP en 8 bits uniquement.
            if img.color().has_alpha() {
                img.to_rgba8()
                    .write_to(&mut w, ImageOutputFormat::WebP)
            } else {
                img.to_rgb8().write_to(&mut w, ImageOutputFormat::WebP)
            }
            .map_err(|e| format!("WebP encoding failed: {e}"))
        }
        TargetFormat::Png => {
            // PNG est intrinsèquement sans perte quel que soit le niveau de
            // compression ; on conserve la profondeur (8/16 bits) et l'alpha
            // d'origine tels que fournis par `img`.
            img.write_to(&mut w, ImageOutputFormat::Png)
                .map_err(|e| format!("PNG encoding failed: {e}"))
        }
        TargetFormat::Tiff => {
            // TIFF non compressé : sans perte, rapide, profondeur/alpha
            // d'origine conservés.
            img.write_to(&mut w, ImageOutputFormat::Tiff)
                .map_err(|e| format!("TIFF encoding failed: {e}"))
        }
    }
}

/// Convertit un fichier source vers le dossier de sortie, avec le nom de
/// base d'origine et la nouvelle extension. Retourne le chemin écrit.
pub fn convert_one(
    input: &Path,
    output_dir: &Path,
    opts: &ConvertOptions,
    collision: crate::cli::CollisionPolicy,
) -> Result<std::path::PathBuf, String> {
    let detected = formats::detect(input);
    if let DetectedFormat::Unknown = detected {
        return Err("format source non reconnu".to_string());
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
