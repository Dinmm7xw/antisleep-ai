#!/bin/bash
set -e

echo "=========================================="
echo "🚀 AntiSleep AI: Automated Vercel Build"
echo "=========================================="

# 1. Download Flutter SDK (stable channel, shallow clone for speed)
if [ ! -d "_flutter/bin" ]; then
  echo "📦 Cloning Flutter SDK (stable channel)..."
  git clone https://github.com/flutter/flutter.git --depth 1 -b stable _flutter
fi

# 2. Add Flutter to PATH
export PATH="$PWD/_flutter/bin:$PATH"

# 3. Disable analytics to prevent prompts/hangs
flutter config --no-analytics

# 4. Enable Web
flutter config --enable-web

echo "🔍 Flutter environment info:"
flutter --version

# 5. Fetch dependencies
echo "📦 Resolving pub dependencies..."
flutter pub get

# 6. Build production release for Web
echo "🏗️ Compiling Flutter Web release..."
flutter build web --release

echo "=========================================="
echo "✅ Build finished successfully! build/web is ready."
echo "=========================================="

