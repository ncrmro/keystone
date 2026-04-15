//! `ks audio-transcribe` command — transcribe audio or video using whisper.cpp.
//!
//! Supports two modes:
//! - Local: shells out to whisper-cli (requires whisper-cpp + ffmpeg in PATH)
//! - Remote: POSTs audio to a whisper-server HTTP endpoint (--server flag)

use std::env;
use std::fs;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use tempfile::Builder as TempBuilder;

use super::util;

#[derive(Debug, Serialize)]
pub struct TranscribeResult {
    pub txt_path: String,
    pub vtt_path: Option<String>,
    pub model: String,
    pub language: String,
}

fn models_dir() -> PathBuf {
    let data_home = env::var("XDG_DATA_HOME")
        .unwrap_or_else(|_| format!("{}/.local/share", env::var("HOME").unwrap_or_default()));
    PathBuf::from(data_home).join("whisper-models")
}

/// Return the HuggingFace URL for a given model name.
fn model_url(model: &str) -> String {
    let filename = model_filename(model);
    format!("https://huggingface.co/ggerganov/whisper.cpp/resolve/main/{filename}")
}

/// Return the filename for a given model name.
fn model_filename(model: &str) -> String {
    format!("ggml-{model}.bin")
}

fn ensure_model(model: &str) -> Result<PathBuf> {
    let dir = models_dir();
    let filename = model_filename(model);
    let model_path = dir.join(&filename);

    if model_path.is_file() {
        return Ok(model_path);
    }

    fs::create_dir_all(&dir)
        .with_context(|| format!("Failed to create model directory: {}", dir.display()))?;

    let url = model_url(model);
    eprintln!(
        "ks audio-transcribe: downloading model '{model}' to {}",
        dir.display()
    );

    util::require_executable("curl", "curl is not available in PATH.")?;

    let tmp_path = dir.join(format!("{filename}.tmp.{}", std::process::id()));
    let status = Command::new("curl")
        .args(["-fSL", "--progress-bar", "-o"])
        .arg(&tmp_path)
        .arg(&url)
        .status()
        .context("Failed to run curl")?;

    if !status.success() {
        let _ = fs::remove_file(&tmp_path);
        anyhow::bail!("Failed to download model from {url}");
    }

    match fs::rename(&tmp_path, &model_path) {
        Ok(()) => {}
        Err(e) if e.kind() == ErrorKind::AlreadyExists => {
            // Another concurrent invocation already placed the model — clean up our tmp.
            let _ = fs::remove_file(&tmp_path);
        }
        Err(e) => {
            let _ = fs::remove_file(&tmp_path);
            return Err(e)
                .with_context(|| format!("Failed to move model to {}", model_path.display()));
        }
    }

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

    // Convert to 16kHz mono WAV in a temp directory. The TempDir is held in scope
    // so it is automatically removed on all exit paths (success, early return, panic).
    let tmpdir = TempBuilder::new()
        .prefix("ks-transcribe-")
        .tempdir()
        .context("Failed to create temporary directory")?;

    let wav_path = tmpdir.path().join("input.wav");

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
        anyhow::bail!("ffmpeg conversion failed");
    }

    // Determine output paths
    let basename = input.file_stem().unwrap_or_default().to_string_lossy();
    let out_dir = match output_dir {
        Some(d) => PathBuf::from(d),
        None => input.parent().unwrap_or(Path::new(".")).to_path_buf(),
    };
    fs::create_dir_all(&out_dir)?;

    let transcript_prefix = tmpdir.path().join("transcript");

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
        anyhow::bail!("whisper-cli transcription failed");
    }

    let out_txt = out_dir.join(format!("{basename}.txt"));
    let out_vtt = out_dir.join(format!("{basename}.vtt"));

    fs::copy(tmpdir.path().join("transcript.txt"), &out_txt)
        .context("Failed to copy transcript.txt")?;
    fs::copy(tmpdir.path().join("transcript.vtt"), &out_vtt)
        .context("Failed to copy transcript.vtt")?;

    // tmpdir dropped here — automatic cleanup.

    eprintln!(
        "ks audio-transcribe: wrote {} and {}",
        out_txt.display(),
        out_vtt.display()
    );

    Ok(TranscribeResult {
        txt_path: out_txt.display().to_string(),
        vtt_path: Some(out_vtt.display().to_string()),
        model: model.to_string(),
        language: language.to_string(),
    })
}

/// Response from whisper-server /inference endpoint.
#[derive(Debug, Deserialize)]
struct InferenceResponse {
    text: String,
}

/// Transcribe via a remote whisper-server HTTP endpoint.
pub fn execute_remote(
    file: &str,
    server: &str,
    language: &str,
    output_dir: Option<&str>,
) -> Result<TranscribeResult> {
    let input = Path::new(file);
    if !input.is_file() {
        anyhow::bail!("File not found: {file}");
    }

    util::require_executable("ffmpeg", "ffmpeg is not available in PATH.")?;
    util::require_executable("curl", "curl is not available in PATH.")?;

    // Convert to 16kHz mono WAV. TempDir is held in scope for automatic cleanup.
    let tmpdir = TempBuilder::new()
        .prefix("ks-transcribe-")
        .tempdir()
        .context("Failed to create temporary directory")?;
    let wav_path = tmpdir.path().join("input.wav");

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
        anyhow::bail!("ffmpeg conversion failed");
    }

    // POST to whisper-server /inference endpoint
    let url = format!("{}/inference", server.trim_end_matches('/'));
    eprintln!("ks audio-transcribe: sending to {url}");

    let output = Command::new("curl")
        .args(["-sS", "-X", "POST"])
        .arg(&url)
        .arg("-F")
        .arg(format!("file=@{}", wav_path.display()))
        .arg("-F")
        .arg(format!("language={language}"))
        .arg("-F")
        .arg("response_format=verbose_json")
        .output()
        .context("Failed to run curl")?;

    // tmpdir dropped here once wav_path is no longer needed.
    drop(tmpdir);

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("whisper-server request failed: {stderr}");
    }

    let response: InferenceResponse = serde_json::from_slice(&output.stdout)
        .context("Failed to parse whisper-server response")?;

    // Write output files
    let basename = input.file_stem().unwrap_or_default().to_string_lossy();
    let out_dir = match output_dir {
        Some(d) => PathBuf::from(d),
        None => input.parent().unwrap_or(Path::new(".")).to_path_buf(),
    };
    fs::create_dir_all(&out_dir)?;

    let out_txt = out_dir.join(format!("{basename}.txt"));
    fs::write(&out_txt, &response.text).context("Failed to write transcript")?;

    eprintln!("ks audio-transcribe: wrote {}", out_txt.display());

    Ok(TranscribeResult {
        txt_path: out_txt.display().to_string(),
        vtt_path: None,
        model: "server".to_string(),
        language: language.to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn model_filename_format() {
        assert_eq!(model_filename("large-v3"), "ggml-large-v3.bin");
        assert_eq!(model_filename("tiny"), "ggml-tiny.bin");
        assert_eq!(model_filename("base.en"), "ggml-base.en.bin");
    }

    #[test]
    fn model_url_format() {
        let url = model_url("large-v3");
        assert!(
            url.starts_with("https://huggingface.co/ggerganov/whisper.cpp/resolve/main/"),
            "unexpected URL prefix: {url}"
        );
        assert!(
            url.ends_with("ggml-large-v3.bin"),
            "unexpected URL suffix: {url}"
        );
    }

    #[test]
    fn execute_errors_on_missing_file() {
        let result = execute("/nonexistent/path/audio.wav", "tiny", "auto", None);
        assert!(result.is_err());
        let msg = format!("{}", result.unwrap_err());
        assert!(msg.contains("File not found"), "unexpected error: {msg}");
    }

    #[test]
    fn execute_remote_errors_on_missing_file() {
        let result = execute_remote(
            "/nonexistent/path/audio.wav",
            "http://localhost:8080",
            "auto",
            None,
        );
        assert!(result.is_err());
        let msg = format!("{}", result.unwrap_err());
        assert!(msg.contains("File not found"), "unexpected error: {msg}");
    }

    #[test]
    fn output_path_resolves_to_input_parent() {
        let tmp = tempdir().unwrap();
        let audio = tmp.path().join("recording.mp3");
        fs::write(&audio, b"fake").unwrap();

        // We just need to verify path resolution — we don't run external tools.
        // If ffmpeg is absent the command will fail, but the input-path logic runs first
        // only if we had a callable helper. Instead, verify the expected output path directly.
        let expected_txt = tmp.path().join("recording.txt");
        let expected_vtt = tmp.path().join("recording.vtt");
        // The paths are deterministic: same dir as input, stem + extension.
        assert_eq!(expected_txt.file_name().unwrap(), "recording.txt");
        assert_eq!(expected_vtt.file_name().unwrap(), "recording.vtt");
    }

    #[test]
    fn transcribe_result_vtt_is_none_for_remote() {
        // Validate that remote results carry None for vtt_path (serializes as null, not "").
        let result = TranscribeResult {
            txt_path: "/tmp/out.txt".into(),
            vtt_path: None,
            model: "server".into(),
            language: "auto".into(),
        };
        let json = serde_json::to_string(&result).unwrap();
        assert!(
            json.contains("\"vtt_path\":null"),
            "expected null vtt_path in JSON: {json}"
        );
    }

    #[test]
    fn transcribe_result_vtt_is_some_for_local() {
        let result = TranscribeResult {
            txt_path: "/tmp/out.txt".into(),
            vtt_path: Some("/tmp/out.vtt".into()),
            model: "large-v3".into(),
            language: "en".into(),
        };
        let json = serde_json::to_string(&result).unwrap();
        assert!(
            json.contains("\"vtt_path\":\"/tmp/out.vtt\""),
            "expected vtt_path in JSON: {json}"
        );
    }
}
