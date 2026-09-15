mod cli;
mod convert;
mod formats;
mod raw;

use clap::Parser;
use rayon::prelude::*;
use serde::Serialize;
use serde_json::json;
use std::io::Write;
use std::sync::atomic::{AtomicUsize, Ordering};

use cli::{Cli, Command};

fn print_json(value: serde_json::Value) {
    let mut out = std::io::stdout().lock();
    let _ = writeln!(out, "{}", value);
    let _ = out.flush();
}

#[derive(Serialize)]
struct FormatsInfo {
    input: Vec<&'static str>,
    output: Vec<OutputFormatInfo>,
}

#[derive(Serialize)]
struct OutputFormatInfo {
    id: &'static str,
    label: &'static str,
    lossless: bool,
}

fn main() {
    let cli = Cli::parse();

    match cli.command {
        Command::Formats => {
            let info = FormatsInfo {
                input: vec![
                    "JPEG", "PNG", "TIFF", "BMP", "GIF", "WebP",
                    "RAW (CR2, CR3, NEF, ARW, DNG, ORF, RAF, RW2, PEF, SRW, X3F, ...)",
                ],
                output: vec![
                    OutputFormatInfo { id: "jpeg", label: "JPEG", lossless: convert::TargetFormat::Jpeg.is_lossless() },
                    OutputFormatInfo { id: "png", label: "PNG", lossless: convert::TargetFormat::Png.is_lossless() },
                    OutputFormatInfo { id: "tiff", label: "TIFF (non compressé)", lossless: convert::TargetFormat::Tiff.is_lossless() },
                    OutputFormatInfo { id: "bmp", label: "BMP", lossless: convert::TargetFormat::Bmp.is_lossless() },
                    OutputFormatInfo { id: "webp", label: "WebP (sans perte)", lossless: convert::TargetFormat::Webp.is_lossless() },
                ],
            };
            print_json(serde_json::to_value(info).unwrap());
        }

        Command::Detect { paths, recursive } => {
            let files = cli::enumerate_images(&paths, recursive);
            let mut counts: std::collections::BTreeMap<String, usize> = Default::default();
            for f in &files {
                let detected = formats::detect(f);
                let label = detected.label();
                *counts.entry(label.clone()).or_insert(0) += 1;
                print_json(json!({
                    "event": "file",
                    "path": f.display().to_string(),
                    "format": label,
                    "is_raw": detected.is_raw(),
                }));
            }
            print_json(json!({
                "event": "summary",
                "total": files.len(),
                "counts": counts,
            }));
        }

        Command::Convert {
            paths,
            recursive,
            output_dir,
            format,
            quality,
            on_collision,
            threads,
        } => {
            if let Some(n) = threads {
                rayon::ThreadPoolBuilder::new()
                    .num_threads(n)
                    .build_global()
                    .ok();
            }

            if let Err(e) = std::fs::create_dir_all(&output_dir) {
                print_json(json!({
                    "event": "fatal_error",
                    "message": format!("impossible de créer le dossier de destination : {e}"),
                }));
                std::process::exit(1);
            }

            let files = cli::enumerate_images(&paths, recursive);
            let total = files.len();
            let opts = convert::ConvertOptions {
                target: format,
                jpeg_quality: quality.clamp(1, 100),
            };

            print_json(json!({ "event": "start", "total": total }));

            let done = AtomicUsize::new(0);
            let ok_count = AtomicUsize::new(0);
            let err_count = AtomicUsize::new(0);

            files.par_iter().for_each(|input| {
                let result = convert::convert_one(input, &output_dir, &opts, on_collision);
                let idx = done.fetch_add(1, Ordering::SeqCst) + 1;
                match result {
                    Ok(output_path) => {
                        ok_count.fetch_add(1, Ordering::SeqCst);
                        print_json(json!({
                            "event": "file_done",
                            "index": idx,
                            "total": total,
                            "input": input.display().to_string(),
                            "output": output_path.display().to_string(),
                            "status": "ok",
                        }));
                    }
                    Err(message) => {
                        err_count.fetch_add(1, Ordering::SeqCst);
                        print_json(json!({
                            "event": "file_done",
                            "index": idx,
                            "total": total,
                            "input": input.display().to_string(),
                            "status": "error",
                            "message": message,
                        }));
                    }
                }
            });

            print_json(json!({
                "event": "summary",
                "total": total,
                "ok": ok_count.load(Ordering::SeqCst),
                "errors": err_count.load(Ordering::SeqCst),
                "output_dir": output_dir.display().to_string(),
            }));
        }
    }
}
