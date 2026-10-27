//! Décodage RAW de secours via LibRaw (embarquée statiquement dans
//! `vendor/libraw-sys`, aucune bibliothèque système requise).
//!
//! Utilisé par `raw.rs` uniquement quand `rawloader`/`imagepipe` échouent —
//! typiquement pour un boîtier absent de la base de `rawloader`. Même
//! contrat que le décodage principal : pleine résolution, aucun
//! recadrage ni redimensionnement (`half_size` reste à 0), balance des
//! blancs enregistrée par l'appareil, espace de sortie sRGB.

use std::ffi::{CStr, CString};
use std::os::raw::c_int;
use std::os::unix::ffi::OsStrExt;
use std::path::Path;

use rsraw_sys as ffi;

use crate::raw::{DecodedRaw16, DecodedRaw8};

/// Instance LibRaw, libérée à la sortie quoi qu'il arrive.
struct Handle(*mut ffi::libraw_data_t);

impl Drop for Handle {
    fn drop(&mut self) {
        // SAFETY: le pointeur vient de `libraw_init` et n'est libéré qu'ici.
        unsafe { ffi::libraw_close(self.0) }
    }
}

/// Image développée en mémoire par LibRaw, libérée à la sortie.
struct Processed(*mut ffi::libraw_processed_image_t);

impl Drop for Processed {
    fn drop(&mut self) {
        // SAFETY: le pointeur vient de `libraw_dcraw_make_mem_image`.
        unsafe { ffi::libraw_dcraw_clear_mem(self.0) }
    }
}

fn libraw_error(code: c_int) -> String {
    // SAFETY: `libraw_strerror` renvoie un pointeur vers une chaîne statique.
    unsafe {
        CStr::from_ptr(ffi::libraw_strerror(code))
            .to_string_lossy()
            .into_owned()
    }
}

/// Développe `path` avec LibRaw en RGB `bits` bits par canal (8 ou 16).
/// Renvoie (largeur, hauteur, octets bruts en ordre natif).
fn develop(path: &Path, bits: u16) -> Result<(u32, u32, Vec<u8>), String> {
    let c_path = CString::new(path.as_os_str().as_bytes())
        .map_err(|_| "chemin invalide (octet nul)".to_string())?;

    // SAFETY: appels FFI sur une instance LibRaw privée à ce thread ; tous
    // les pointeurs sont vérifiés avant usage et libérés par les gardes.
    unsafe {
        let raw = ffi::libraw_init(0);
        if raw.is_null() {
            return Err("LibRaw : initialisation impossible".to_string());
        }
        let handle = Handle(raw);

        {
            let p = &mut (*handle.0).params;
            p.output_bps = bits as c_int;
            p.output_color = 1; // sRGB
            p.use_camera_wb = 1; // balance des blancs de l'appareil
            p.no_auto_bright = 1; // pas de correction de luminosité automatique
            p.gamm[0] = 1.0 / 2.4; // courbe sRGB (comme le pipeline principal)
            p.gamm[1] = 12.92;
            p.half_size = 0; // jamais de réduction de résolution
        }

        let rc = ffi::libraw_open_file(handle.0, c_path.as_ptr());
        if rc != 0 {
            return Err(format!("LibRaw : {}", libraw_error(rc)));
        }
        let rc = ffi::libraw_unpack(handle.0);
        if rc != 0 {
            return Err(format!("LibRaw : {}", libraw_error(rc)));
        }
        let rc = ffi::libraw_dcraw_process(handle.0);
        if rc != 0 {
            return Err(format!("LibRaw : {}", libraw_error(rc)));
        }

        let mut errc: c_int = 0;
        let img = ffi::libraw_dcraw_make_mem_image(handle.0, &mut errc);
        if img.is_null() {
            return Err(format!("LibRaw : {}", libraw_error(errc)));
        }
        let img = Processed(img);

        let (kind, w, h, colors, depth, size) = {
            let i = &*img.0;
            (
                i.type_,
                i.width as u32,
                i.height as u32,
                i.colors,
                i.bits,
                i.data_size as usize,
            )
        };
        if kind != ffi::LibRaw_image_formats_LIBRAW_IMAGE_BITMAP || colors != 3 || depth != bits {
            return Err(format!(
                "LibRaw : image développée inattendue (type {kind}, {colors} canaux, {depth} bits)"
            ));
        }
        let expected = w as usize * h as usize * 3 * (bits as usize / 8);
        if size != expected || w == 0 || h == 0 {
            return Err(format!(
                "LibRaw : taille d'image incohérente ({size} octets, {expected} attendus)"
            ));
        }
        let data = std::slice::from_raw_parts((*img.0).data.as_ptr(), size);
        Ok((w, h, data.to_vec()))
    }
}

pub fn decode_8bit(path: &Path) -> Result<DecodedRaw8, String> {
    let (width, height, rgb) = develop(path, 8)?;
    Ok(DecodedRaw8 { width, height, rgb })
}

pub fn decode_16bit(path: &Path) -> Result<DecodedRaw16, String> {
    let (width, height, bytes) = develop(path, 16)?;
    let rgb = bytes
        .chunks_exact(2)
        .map(|c| u16::from_ne_bytes([c[0], c[1]]))
        .collect();
    Ok(DecodedRaw16 { width, height, rgb })
}

#[cfg(test)]
mod tests {
    use super::*;

    const W: u32 = 64;
    const H: u32 = 48;
    const RAW_VALUE: u16 = 20000;

    /// DNG minimal non compressé : 64x48, 16 bits, mosaïque RGGB, valeur
    /// uniforme, matrice couleur identité, balance des blancs neutre.
    fn synthetic_dng() -> Vec<u8> {
        const SHORT: u16 = 3;
        const LONG: u16 = 4;
        const ASCII: u16 = 2;
        const BYTE: u16 = 1;
        const RATIONAL: u16 = 5;
        const SRATIONAL: u16 = 10;

        let mut buf: Vec<u8> = b"II*\0\0\0\0\0".to_vec();
        for _ in 0..(W * H) {
            buf.extend_from_slice(&RAW_VALUE.to_le_bytes());
        }
        let mut put = |buf: &mut Vec<u8>, bytes: &[u8]| -> u32 {
            if buf.len() % 2 == 1 {
                buf.push(0);
            }
            let off = buf.len() as u32;
            buf.extend_from_slice(bytes);
            off
        };
        let make = put(&mut buf, b"FakeCam\0");
        let model = put(&mut buf, b"Synthetic DNG\0");
        let mut cm = Vec::new();
        for (n, d) in [(1i32, 1i32), (0, 1), (0, 1), (0, 1), (1, 1), (0, 1), (0, 1), (0, 1), (1, 1)] {
            cm.extend_from_slice(&n.to_le_bytes());
            cm.extend_from_slice(&d.to_le_bytes());
        }
        let cm_off = put(&mut buf, &cm);
        let mut asn = Vec::new();
        for _ in 0..3 {
            asn.extend_from_slice(&1u32.to_le_bytes());
            asn.extend_from_slice(&1u32.to_le_bytes());
        }
        let asn_off = put(&mut buf, &asn);

        let mut ent: Vec<(u16, u16, u32, u32)> = vec![
            (254, LONG, 1, 0),
            (256, LONG, 1, W),
            (257, LONG, 1, H),
            (258, SHORT, 1, 16),
            (259, SHORT, 1, 1),
            (262, SHORT, 1, 32803),
            (271, ASCII, 8, make),
            (272, ASCII, 14, model),
            (273, LONG, 1, 8),
            (274, SHORT, 1, 1),
            (277, SHORT, 1, 1),
            (278, LONG, 1, H),
            (279, LONG, 1, W * H * 2),
            (284, SHORT, 1, 1),
            (33421, SHORT, 2, 2 | (2 << 16)),
            (33422, BYTE, 4, 0 | (1 << 8) | (1 << 16) | (2 << 24)),
            (50706, BYTE, 4, 1 | (4 << 8)),
            (50708, ASCII, 14, model),
            (50714, SHORT, 1, 0),
            (50717, LONG, 1, 65535),
            (50721, SRATIONAL, 9, cm_off),
            (50728, RATIONAL, 3, asn_off),
            (50778, SHORT, 1, 21),
        ];
        ent.sort();
        if buf.len() % 2 == 1 {
            buf.push(0);
        }
        let ifd_off = buf.len() as u32;
        buf.extend_from_slice(&(ent.len() as u16).to_le_bytes());
        for (t, ty, c, v) in ent {
            buf.extend_from_slice(&t.to_le_bytes());
            buf.extend_from_slice(&ty.to_le_bytes());
            buf.extend_from_slice(&c.to_le_bytes());
            buf.extend_from_slice(&v.to_le_bytes());
        }
        buf.extend_from_slice(&0u32.to_le_bytes());
        buf[4..8].copy_from_slice(&ifd_off.to_le_bytes());
        buf
    }

    fn write_dng(name: &str) -> (std::path::PathBuf, std::path::PathBuf) {
        let dir = std::env::temp_dir().join(format!("cie-libraw-{}-{name}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let f = dir.join("synthetic.dng");
        std::fs::write(&f, synthetic_dng()).unwrap();
        (dir, f)
    }

    #[test]
    fn decodes_full_resolution_8bit_neutral_and_not_black() {
        let (dir, f) = write_dng("8");
        let d = decode_8bit(&f).expect("LibRaw doit décoder le DNG synthétique");
        // Pleine résolution : ni recadrage ni réduction.
        assert_eq!((d.width, d.height), (W, H));
        assert_eq!(d.rgb.len(), (W * H * 3) as usize);
        // Gris neutre (R≈G≈B) et ni noir ni saturé au centre de l'image.
        let i = ((H / 2 * W + W / 2) * 3) as usize;
        let (r, g, b) = (d.rgb[i] as i32, d.rgb[i + 1] as i32, d.rgb[i + 2] as i32);
        assert!((r - g).abs() <= 3 && (g - b).abs() <= 3, "pas neutre : {r},{g},{b}");
        assert!((60..=250).contains(&g), "valeur hors plage : {g}");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn decodes_full_resolution_16bit() {
        let (dir, f) = write_dng("16");
        let d = decode_16bit(&f).expect("LibRaw doit décoder le DNG synthétique");
        assert_eq!((d.width, d.height), (W, H));
        assert_eq!(d.rgb.len(), (W * H * 3) as usize);
        let i = ((H / 2 * W + W / 2) * 3) as usize;
        let g = d.rgb[i + 1] as i32;
        // 16 bits réels : bien au-delà de la plage 0..=255.
        assert!(g > 1000, "valeur 16 bits suspecte : {g}");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn fallback_path_converts_when_primary_decoder_fails() {
        let (dir, f) = write_dng("fb");
        let r = crate::raw::decode_with_fallback_for_tests(&f);
        assert!(r.is_ok(), "{r:?}");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn invalid_file_gives_a_libraw_error() {
        let dir = std::env::temp_dir().join(format!("cie-libraw-bad-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let f = dir.join("bad.arw");
        std::fs::write(&f, b"pas un RAW").unwrap();
        let msg = decode_8bit(&f).unwrap_err();
        assert!(msg.starts_with("LibRaw :"), "{msg}");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
