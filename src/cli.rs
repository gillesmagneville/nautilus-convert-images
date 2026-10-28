use clap::{Parser, Subcommand, ValueEnum};
use std::path::{Path, PathBuf};

use crate::convert::TargetFormat;
use crate::formats;

#[derive(Parser)]
#[command(
    name = "convert-images-engine",
    version,
    about = "Image conversion engine (RAW, JPEG, PNG, TIFF, BMP, WebP) for the nautilus-convert-images Nautilus extension"
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Command,
}

#[derive(Subcommand)]
pub enum Command {
    /// Detects the format of the image files found in the given paths.
    /// Emits one JSON line per file on stdout, plus a final summary.
    Detect {
        /// Files and/or folders to analyze.
        paths: Vec<PathBuf>,
        /// Search subfolders.
        #[arg(short, long)]
        recursive: bool,
    },

    /// Converts the image files found to the target format.
    /// Emits one JSON progress line per file on stdout.
    Convert {
        /// Files and/or folders to convert.
        paths: Vec<PathBuf>,
        /// Search subfolders.
        #[arg(short, long)]
        recursive: bool,
        /// Destination folder (created if needed).
        #[arg(short, long)]
        output_dir: PathBuf,
        /// Target format.
        #[arg(short, long, value_enum)]
        format: TargetFormat,
        /// JPEG quality (1-100), ignored for other formats.
        #[arg(long, default_value_t = 100)]
        quality: u8,
        /// What to do when the destination file already exists.
        #[arg(long, value_enum, default_value = "rename")]
        on_collision: CollisionPolicy,
        /// Number of threads (default: all available cores).
        #[arg(long)]
        threads: Option<usize>,
    },

    /// Lists the supported source and target formats (for the GUI).
    Formats,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum CollisionPolicy {
    Skip,
    Rename,
    Overwrite,
}

/// Énumère récursivement (ou non) les fichiers image plausibles à partir
/// d'une liste de chemins (fichiers et/ou dossiers).
pub fn enumerate_images(paths: &[PathBuf], recursive: bool) -> Vec<PathBuf> {
    let mut out = Vec::new();
    for p in paths {
        collect_from_path(p, recursive, &mut out);
    }
    out
}

fn collect_from_path(path: &Path, recursive: bool, out: &mut Vec<PathBuf>) {
    if path.is_file() {
        // Un fichier explicitement sélectionné est toujours pris en compte,
        // même si son extension n'est pas reconnue (la détection par
        // contenu tranchera).
        out.push(path.to_path_buf());
        return;
    }
    if path.is_dir() {
        let walker = if recursive {
            walkdir::WalkDir::new(path)
        } else {
            walkdir::WalkDir::new(path).max_depth(1)
        };
        for entry in walker.into_iter().filter_map(|e| e.ok()) {
            let p = entry.path();
            if p.is_file() && (p == path || formats::has_known_image_extension(p)) {
                if p != path {
                    out.push(p.to_path_buf());
                }
            }
        }
    }
}
