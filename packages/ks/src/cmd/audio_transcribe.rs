//! `ks audio-transcribe` command — transcribe audio or video locally using whisper.cpp.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{Context, Result};
use serde::Serialize;

use super::util;

#[derive(Debug, Serialize)]
pub struct TranscribeResult {
    pub txt_path: String,
    pub vtt_path: String,
    pub model: String,
    pub language: String,
}

fn models_dir() -> PathBuf {
    let data_home = env::var("XDG_DATA_HOME")
        .unwrap_or_else(|_| format!("{}/.local/share", env::var("HOME").unwrap_or_default()));
    PathBuf::from(data_home).join("whisper-models")
}

fn ensure_model(model: &str) -> Result<PathBuf> {
    let dir = models_dir();
    let filename = format!("ggml-{model}.bin");
    let model_path = dir.join(&filename);

    if model_path.is_file() {
        return Ok(model_path);
    }

    fs::create_dir_all(&dir)
        .with_context(|| format!("Failed to create model directory: {}", dir.display()))?;

    let url = format!("https://huggingface.co/ggerganov/whisper.cpp/resolve/main/{filename}");
    eprintln!(
        "ks audio-transcribe: downloading model '{model}' to {}",
        dir.display()
    );

    util::require_executable("curl", "curl is not available in PATH.")?;

    let tmp_path = dir.join(format!("{filename}.tmp"));
    let status = Command::new("curl")
        .args(["-fSL", "--progress-bar", "-o"])
        .arg(&tmp_path)
        .arg(&url)
        .status()
        .context("Failed to run curl")?;

    if !status.success() {
        anyhow::bail!("Failed to download model from {url}");
    }

    fs::rename(&tmp_path, &model_path)
        .with_context(|| format!("Failed to move model to {}", model_path.display()))?;

    Ok(model_path)
}

pub fn execute(
    file: &str,
    model: &str,
    language: &str,
    output_dir: Option<&str>,
) -> Result<TranscribeResult> {
    let input = Path::new(file);
    if !input.is_file() {
        anyhow::bail!("File not found: {file}");
    }

    util::require_executable("ffmpeg", "ffmpeg is not available in PATH.")?;
    util::require_executable(
        "whisper-cli",
        "whisper-cli is not available in PATH. Install whisper-cpp.",
    )?;

    let model_path = ensure_model(model)?;

    // Convert to 16kHz mono WAV in a temp directory
    let tmpdir = env::temp_dir().join(format!("ks-transcribe-{}", std::process::id()));
    fs::create_dir_all(&tmpdir)?;

    let wav_path = tmpdir.join("input.wav");

    eprintln!("ks audio-transcribe: converting to WAV");
    let status = Command::new("ffmpeg")
        .args(["-y", "-i"])
        .arg(file)
        .args(["-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le"])
        .arg(&wav_path)
        .args(["-loglevel", "error"])
        .status()
        .context("Failed to run ffmpeg")?;

    if !status.success() {
        let _ = fs::remove_dir_all(&tmpdir);
        anyhow::bail!("ffmpeg conversion failed");
    }

    // Determine output paths
    let basename = input.file_stem().unwrap_or_default().to_string_lossy();
    let out_dir = match output_dir {
        Some(d) => PathBuf::from(d),
        None => input.parent().unwrap_or(Path::new(".")).to_path_buf(),
    };
    fs::create_dir_all(&out_dir)?;

    let transcript_prefix = tmpdir.join("transcript");

    eprintln!("ks audio-transcribe: model={model} lang={language} file={file}");
    let status = Command::new("whisper-cli")
        .arg("--model")
        .arg(&model_path)
        .arg("--language")
        .arg(language)
        .args(["--output-txt", "--output-vtt"])
        .arg("--output-file")
        .arg(&transcript_prefix)
        .arg("--file")
        .arg(&wav_path)
        .args(["--no-prints"])
        .status()
        .context("Failed to run whisper-cli")?;

    if !status.success() {
        let _ = fs::remove_dir_all(&tmpdir);
        anyhow::bail!("whisper-cli transcription failed");
    }

    let out_txt = out_dir.join(format!("{basename}.txt"));
    let out_vtt = out_dir.join(format!("{basename}.vtt"));

    fs::copy(tmpdir.join("transcript.txt"), &out_txt).context("Failed to copy transcript.txt")?;
    fs::copy(tmpdir.join("transcript.vtt"), &out_vtt).context("Failed to copy transcript.vtt")?;

    let _ = fs::remove_dir_all(&tmpdir);

    eprintln!(
        "ks audio-transcribe: wrote {} and {}",
        out_txt.display(),
        out_vtt.display()
    );

    Ok(TranscribeResult {
        txt_path: out_txt.display().to_string(),
        vtt_path: out_vtt.display().to_string(),
        model: model.to_string(),
        language: language.to_string(),
    })
}
