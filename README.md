# Qayd (قَيْد) — Open-Source AI Lecture Summarizer 🎓

> **"قَيِّدُوا الْعِلْمَ بِالْكِتَابِ"** — *"Bind knowledge by writing it down."*

**Qayd** is an open-source, local-first Flutter application that transforms recorded or imported bilingual lectures into accurate transcripts, timestamped visual notes, and structured academic study guides.

**Supported platforms:** Android, iOS, and Web.

---

## 🚀 Core Features

- **🎙️ Live Lecture Audio Recording:**
  Records directly via the device microphone configured natively to **44.1 kHz Mono 64 kbps AAC** with auto-gain (`AndroidAudioSource.mic`, Bluetooth hijack disabled) for clear bilingual transcription without multi-channel overhead.
- **📸 Timestamped Lecture Photo Capture:**
  Capture photos of lecture boards and slides while recording audio. Each photo is automatically linked to the exact elapsed recording timestamp and supports tap-to-seek playback and full-screen viewing in the lecture detail view.
- **📁 Audio File Import & Smart Chunking:**
  Supports importing `.mp3`, `.m4a`, `.wav`, `.aac`, `.ogg`, `.webm`, and `.flac` files. Long or large recordings are automatically compressed and split via FFmpeg into Whisper-optimal `16 kHz Mono 32 kbps MP3` chunks, transcribed sequentially, and merged with contiguous timestamps so Groq Whisper never hits file-size or duration limits.
- **⚡ Bilingual Speech-to-Text with Language Auto-Detection:**
  Powered by **Groq Whisper-large-v3** using `verbose_json` for sub-second word and segment timestamps. Features automatic speech language detection and a technical glossary prompt (`API, database, backend, CPU, thread, process...`) that preserves Latin script for technical terms in Arabic-English code-switched lectures.
- **🛡️ 4-Layer Anti-Hallucination Shield:**
  Automated filtering that suppresses Whisper silence hallucinations:
  1. *Acoustic Confidence Filter:* Drops segments where `no_speech_prob > 0.6` and `avg_logprob < -1.0`.
  2. *Repetition Loop Filter:* Drops segments where `compression_ratio > 2.4`.
  3. *Phantom Credit Blocklist:* Strips known Whisper hallucination strings and ghost credits.
  4. *Consecutive Deduplication:* Drops identical consecutive phrases repeated across silence.
- **🧠 Structured Academic Summarization:**
  Powered by **Google Gemini Flash** with strict JSON schema enforcement:
  - **Overview:** Crisp conceptual synthesis of the lecture.
  - **Topic Breakdown:** Chronological topic cards with clickable `[MM:SS]` audio timestamps.
  - **Key Points:** High-yield bullet points emphasizing core concepts.
  - **Key Terms & Definitions:** Glossary of technical terms encountered during the lecture.
  - **Bilingual Summary Toggle:** Switch between Arabic and English summaries anytime.
- **⏱️ Tap-to-Seek Synchronized Audio Player:**
  Tapping any transcript segment or captured photo immediately seeks the audio player to that exact timestamp while highlighting the active segment in real time.
- **📄 Publication-Grade Arabic PDF Export:**
  Built-in PDF generation engine (`PdfExportService`) handling bidirectional Arabic text shaping into Unicode Presentation Forms-B (`0xFE70`–`0xFEFF`), producing clean, print-ready bilingual lecture briefs.
- **🔑 In-App API Key Settings:**
  Enter your own **Groq** and **Gemini** API keys once directly from the in-app **Settings** screen—stored locally on-device with no backend or mandatory account required.
- **💾 Offline-First Local Persistence:**
  All lectures, photos, folders, and settings are stored locally on the device using **Hive CE**, with automatic orphan-file cleanup on deletion.
- **🌐 Native Bilingual UI (EN / AR) with RTL Support:**
  Full English and Arabic interface with instant RTL switching and Light/Dark Material 3 themes.
- **🗂️ Subject Folders, Search & Transcript Editing:**
  Organize lectures into custom folders, search across titles, transcripts, and summaries, and edit transcripts directly inside the app.

---

## 🏗️ Project Architecture

```text
lib/
├── core/
│   ├── constants/
│   │   └── api_constants.dart             # API endpoints, models, and code-switching glossary
│   └── theme/
│       └── qayd_theme.dart                # Material 3 Academic Indigo theme (Light & Dark)
├── data/
│   ├── models/
│   │   ├── folder_model.dart              # QaydFolder entity
│   │   └── qayd_model.dart                # Qayd, LecturePhoto, TranscriptSegment, QaydSummary, KeyTerm
│   └── services/
│       ├── audio_compression_service.dart # FFmpeg 16kHz Mono 32kbps MP3 compressor
│       ├── audio_picker_service.dart      # FilePicker for external lecture audio imports
│       ├── audio_recording_service.dart   # 44.1kHz Mono 64kbps AAC mic recording service
│       ├── audio_splitter_service.dart    # FFmpeg segment splitter for long recordings
│       ├── gemini_summary_service.dart    # Gemini Flash structured summary client
│       ├── groq_whisper_service.dart      # Groq Whisper client (single & chunked) + Hallucination Shield
│       ├── pdf_export_service.dart        # Arabic/English PDF export engine
│       ├── photo_capture_service.dart     # Timestamped lecture photo storage helper
│       └── storage_service.dart           # Hive CE offline storage (lectures, folders, settings)
├── providers/
│   └── qayd_provider.dart                 # Central ChangeNotifier orchestrating state & AI pipeline
├── screens/
│   ├── detail/
│   │   └── detail_screen.dart             # Audio player, Tap-to-Seek transcript, photos & summary
│   ├── home/
│   │   └── home_screen.dart               # Folder chips, search, lecture list & settings entry
│   ├── processing/
│   │   └── processing_screen.dart         # Real-time multi-stage pipeline status checklist
│   ├── record/
│   │   ├── photo_capture_screen.dart      # Live camera capture screen during recording
│   │   └── record_screen.dart             # Visualizer, live timer, pause/resume/stop & camera trigger
│   ├── settings/
│   │   └── settings_screen.dart           # Local Groq & Gemini API key configuration
│   └── splash/
│       └── qayd_splash_gate.dart          # Animated splash screen with Android 12+ compatibility
├── widgets/
│   └── qayd_actions.dart                  # Shared rename, move, edit transcript, and delete dialogs
└── main.dart                              # App entry point, MultiProvider & MaterialApp
```

---

## ⚙️ Setup & Running

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (`^3.13.4` or later)
- Android Studio / VS Code with Flutter & Android SDK tooling
- A [Groq API Key](https://console.groq.com/keys) (for Whisper transcription) and a [Google Gemini API Key](https://aistudio.google.com/apikey) (for structured summarization)

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/waseeld/qayd.git
   cd qayd
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run the app:**
   ```bash
   flutter run
   ```
   Open **Settings** (gear icon in the top bar) and enter your Groq and Gemini API keys once—they are saved locally on your device.

   *(Optional)* You can also supply default compile-time keys via `.env`:
   ```bash
   cp .env.example .env
   # Add GROQ_API_KEY and GEMINI_API_KEY to .env
   flutter run --dart-define-from-file=.env
   ```

---

## 🧪 Testing & Verification

- **Run all automated tests:**
  ```bash
  flutter test
  ```
  *(**48/48 tests passing**)*

- **Run static code analysis:**
  ```bash
  flutter analyze
  ```
  *(**0 issues found**)*

---

## 🤝 Contributing

Contributions, bug reports, and feature ideas are welcome! Feel free to open an issue or submit a pull request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feat/your-feature`)
3. Run `flutter analyze` and `flutter test`
4. Commit your changes and open a pull request

---

## 📜 Background & Credits

Qayd originally started as a student project for the **Android / Mobile Application Development course (CS442)** at the **Faculty of Computer Science & Information Technology, Islamic University of Madinah**, under the supervision of **Mr. Ahmed Almatrafi**, and has since evolved into an open-source project.

### Contributors
- **Wasel Mohammed Almahri**
- **Halim Tayeb**

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
