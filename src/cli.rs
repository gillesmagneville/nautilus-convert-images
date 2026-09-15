use clap::{Parser, Subcommand, ValueEnum};
use std::path::{Path, PathBuf};

use crate::convert::TargetFormat;
use crate::formats;

#[derive(Parser)]
#[command(
    name = "convert-images-engine",
    version,
    about = "Moteur de conversion d'images (RAW, JPEG, PNG, TIFF, BMP, WebP) pour l'extension Nautilus nautilus-convert-images"
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Command,
}

#[derive(Subcommand)]
pub enum Command {
    /// Détecte le format des fichiers image trouvés dans les chemins donnés.
    /// Émet une ligne JSON par fichier sur stdout, plus un résumé final.
    Detect {
        /// Fichiers et/ou dossiers à analyser.
        paths: Vec<PathBuf>,
        /// Parcourir les sous-dossiers.
        #[arg(short, long)]
        recursive: bool,
    },

    /// Convertit les fichiers image trouvés vers le format cible.
    /// Émet une ligne JSON de progression par fichier sur stdout.
    Convert {
        /// Fichiers et/ou dossiers à convertir.
        paths: Vec<PathBuf>,
        /// Parcourir les sous-dossiers.
        #[arg(short, long)]
        recursive: bool,
        /// Dossier de destination (créé si nécessaire).
        #[arg(short, long)]
        output_dir: PathBuf,
        /// Format cible.
        #[arg(short, long, value_enum)]
        format: TargetFormat,
        /// Qualité JPEG (1-100), ignorée pour les autres formats.
        #[arg(long, default_value_t = 100)]
        quality: u8,
        /// Politique en cas de fichier de destination déjà existant.
        #[arg(long, value_enum, default_value = "rename")]
        on_collision: CollisionPolicy,
        /// Nombre de threads (par défaut : tous les cœurs disponibles).
        #[arg(long)]
        threads: Option<usize>,
    },

    /// Liste les formats source et cible supportés (pour l'IHM).
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
