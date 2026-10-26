# Warung Lupi Engineering & CI/CD Guidelines

## Aturan Kompilasi & Build APK (PENTING)
1. **Dilarang Build APK di Lokal**:
   - Jangan pernah menjalankan `flutter build apk` atau `flutter build appbundle` secara langsung di mesin lokal.
   - Kompilasi lokal memakan waktu, CPU, dan resource yang berat pada perangkat pengguna.
2. **Semua Build APK Didelegasikan ke GitHub Actions**:
   - **CI Build (Push ke `main`)**: Workflow `.github/workflows/flutter-ci.yml` otomatis berjalan, memvalidasi lint/test, dan mengompilasi APK serta mengunggahnya sebagai GitHub Artifact (`app-release-apk`).
   - **Release Build (Git Tag `v*`)**: Workflow `.github/workflows/release.yml` otomatis berjalan saat tag versi dipush (misal `v1.3.7`), mengompilasi APK, dan langsung memublikasikannya di GitHub Releases dengan file APK terlampir.
3. **Prosedur Pelaporan**:
   - Pantau status build menggunakan GitHub CLI: `gh run list --limit 3` dan `gh run view <run-id>`.
   - Laporkan hasil build, exit status CI remote, dan tautan download APK/release resmi di GitHub kepada pengguna.
