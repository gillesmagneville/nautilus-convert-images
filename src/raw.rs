//! Décodage des fichiers RAW en image RGB pleine résolution, sans
//! recadrage ni redimensionnement.
//!
//! `imagepipe` (basé sur `rawloader`) applique le pipeline standard
//! (dématriçage, balance des blancs telle qu'enregistrée par l'appareil,
//! conversion couleur, gamma) sans jamais recadrer ni réduire la
//! résolution tant que `maxwidth`/`maxheight` restent à 0 et qu'aucune
//! opération de recadrage n'est ajoutée — ce que ce module garantit en
//! utilisant le pipeline par défaut sans le modifier.
//!
//! Ordre de décodage : `rawloader`/`imagepipe` d'abord ; si le fichier ne
//! peut pas être décodé (typiquement un boîtier absent de la base de
//! `rawloader`), repli sur LibRaw (`libraw.rs`) ; si LibRaw échoue aussi,
//! l'erreur combinée est remontée et le lot continue avec le fichier suivant.

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
        // imagepipe masque la vraie cause : il essaie rawloader, puis
        // image::open, et renvoie un message générique si les deux échouent.
        // On refait donc l'appel à rawloader pour remonter son erreur réelle
        // (boîtier non pris en charge, compression non gérée, etc.).
        match rawloader::decode_file(path) {
            Err(raw_err) => format!("cannot open RAW file: {raw_err}"),
            Ok(_) => format!("cannot open RAW file: {e}"),
        }
    })?;
    // Résolution pleine, aucune limite -> aucun redimensionnement.
    pipeline.globals.settings.maxwidth = 0;
    pipeline.globals.settings.maxheight = 0;
    // pipeline.ops.rotatecrop reste à sa valeur par défaut (no-op) : pas de
    // recadrage ajouté au-delà de la zone active du capteur gérée par
    // rawloader/imagepipe lui-même (identique à ce que produirait
    // l'appareil photo).
    Ok(pipeline)
}

/// Exécute un décodeur en transformant une panique interne (fichier
/// corrompu, bug de bibliothèque) en erreur, pour que le lot continue.
fn guarded<T>(name: &str, f: impl FnOnce() -> Result<T, String>) -> Result<T, String> {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)) {
        Ok(r) => r,
        Err(_) => Err(format!("{name}: internal decoder error (corrupted file?)")),
    }
}

/// Combine l'erreur du décodeur principal et celle du repli LibRaw.
fn combined(primary: String, fallback: String) -> String {
    // Les messages de rawloader contiennent des retours à la ligne : on les
    // aplatit pour que l'erreur reste lisible sur une ligne du journal.
    let flat = |s: String| s.split_whitespace().collect::<Vec<_>>().join(" ");
    format!("{} ; LibRaw fallback: {}", flat(primary), flat(fallback))
}

/// Essaie `primary` ; s'il échoue, essaie `fallback` ; si les deux
/// échouent, remonte les deux erreurs (le lot continue avec le fichier
/// suivant, c'est l'appelant qui affiche l'erreur).
fn with_fallback<T>(
    primary: impl FnOnce() -> Result<T, String>,
    fallback: impl FnOnce() -> Result<T, String>,
) -> Result<T, String> {
    match primary() {
        Ok(v) => Ok(v),
        Err(p) => fallback().map_err(|f| combined(p, f)),
    }
}

/// Décode un fichier RAW en RGB 8 bits par canal, pleine résolution.
/// Adapté aux formats de sortie 8 bits (JPEG, BMP, WebP).
pub fn decode_8bit(path: &Path) -> Result<DecodedRaw8, String> {
    with_fallback(
        || guarded("rawloader", || decode_8bit_rawloader(path)),
        || guarded("LibRaw", || crate::libraw::decode_8bit(path)),
    )
}

/// Décode un fichier RAW en RGB 16 bits par canal, pleine résolution.
/// Adapté aux formats de sortie sans perte à profondeur étendue (TIFF, PNG).
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

/// Test uniquement : simule un décodeur principal en échec (boîtier
/// inconnu) pour vérifier que le repli LibRaw prend bien le relais.
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
            with_fallback(|| Ok(1), || panic!("le repli ne doit pas être appelé"));
        assert_eq!(r, Ok(1));
    }

    #[test]
    fn primary_fails_fallback_used() {
        let r: Result<u8, String> = with_fallback(|| Err("boîtier inconnu".into()), || Ok(2));
        assert_eq!(r, Ok(2));
    }

    #[test]
    fn both_fail_errors_are_combined() {
        let r: Result<u8, String> =
            with_fallback(|| Err("erreur A".into()), || Err("erreur B".into()));
        let msg = r.unwrap_err();
        assert!(msg.contains("erreur A") && msg.contains("erreur B"), "{msg}");
    }

    #[test]
    fn panic_becomes_an_error() {
        let r: Result<u8, String> = guarded("test", || panic!("boum"));
        assert!(r.unwrap_err().contains("internal decoder error"));
    }

    #[test]
    fn garbage_file_reports_both_decoders_and_does_not_crash() {
        let dir = std::env::temp_dir().join(format!("cie-raw-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let f = dir.join("garbage.arw");
        std::fs::write(&f, b"ceci n'est pas un fichier RAW").unwrap();
        let msg = decode_8bit(&f).unwrap_err();
        assert!(msg.contains("LibRaw fallback"), "{msg}");
        let msg16 = decode_16bit(&f).unwrap_err();
        assert!(msg16.contains("LibRaw fallback"), "{msg16}");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
