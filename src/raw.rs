//! Décodage des fichiers RAW en image RGB pleine résolution, sans
//! recadrage ni redimensionnement.
//!
//! `imagepipe` (basé sur `rawloader`) applique le pipeline standard
//! (dématriçage, balance des blancs telle qu'enregistrée par l'appareil,
//! conversion couleur, gamma) sans jamais recadrer ni réduire la
//! résolution tant que `maxwidth`/`maxheight` restent à 0 et qu'aucune
//! opération de recadrage n'est ajoutée — ce que ce module garantit en
//! utilisant le pipeline par défaut sans le modifier.

use std::path::Path;

pub struct DecodedRaw8 {
    pub width: u32,
    pub height: u32,
    pub rgb: Vec<u8>,
}

pub struct DecodedRaw16 {
    pub width: u32,
    pub height: u32,
    pub rgb: Vec<u16>,
}

fn new_pipeline(path: &Path) -> Result<imagepipe::Pipeline, String> {
    let mut pipeline = imagepipe::Pipeline::new_from_file(path)
        .map_err(|e| format!("ouverture RAW impossible : {e}"))?;
    // Résolution pleine, aucune limite -> aucun redimensionnement.
    pipeline.globals.settings.maxwidth = 0;
    pipeline.globals.settings.maxheight = 0;
    // pipeline.ops.rotatecrop reste à sa valeur par défaut (no-op) : pas de
    // recadrage ajouté au-delà de la zone active du capteur gérée par
    // rawloader/imagepipe lui-même (identique à ce que produirait
    // l'appareil photo).
    Ok(pipeline)
}

/// Décode un fichier RAW en RGB 8 bits par canal, pleine résolution.
/// Adapté aux formats de sortie 8 bits (JPEG, BMP, WebP).
pub fn decode_8bit(path: &Path) -> Result<DecodedRaw8, String> {
    let mut pipeline = new_pipeline(path)?;
    let img = pipeline
        .output_8bit(None)
        .map_err(|e| format!("décodage RAW impossible : {e}"))?;
    Ok(DecodedRaw8 {
        width: img.width as u32,
        height: img.height as u32,
        rgb: img.data,
    })
}

/// Décode un fichier RAW en RGB 16 bits par canal, pleine résolution.
/// Adapté aux formats de sortie sans perte à profondeur étendue (TIFF, PNG).
pub fn decode_16bit(path: &Path) -> Result<DecodedRaw16, String> {
    let mut pipeline = new_pipeline(path)?;
    let img = pipeline
        .output_16bit(None)
        .map_err(|e| format!("décodage RAW impossible : {e}"))?;
    Ok(DecodedRaw16 {
        width: img.width as u32,
        height: img.height as u32,
        rgb: img.data,
    })
}
