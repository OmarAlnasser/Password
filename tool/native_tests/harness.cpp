// Test harness for the pure (standard-library-only) part of
// windows/runner/platform_channel.cpp. run_tests.py cuts the text between the
// PURE-BEGIN and PURE-END markers out of that file into pure_region.inc and
// compiles this program around it, so the code under test is the code the
// Windows runner ships. Each sub-command reads files / argv and prints plain
// text; run_tests.py checks the output against Python and Pillow references.
//
// Never put real credentials in test data: use synthetic look-alikes.

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include <utility>
#include <vector>

namespace {
#include "pure_region.inc"
}  // namespace

namespace {

std::vector<uint8_t> ReadFile(const char* path) {
  std::ifstream in(path, std::ios::binary);
  return std::vector<uint8_t>((std::istreambuf_iterator<char>(in)),
                              std::istreambuf_iterator<char>());
}

void WriteFile(const char* path, const std::vector<uint8_t>& bytes) {
  std::ofstream out(path, std::ios::binary);
  out.write(reinterpret_cast<const char*>(bytes.data()),
            static_cast<std::streamsize>(bytes.size()));
}

std::string Hex(const std::string& bytes) {
  static const char* digits = "0123456789abcdef";
  std::string out;
  for (const char c : bytes) {
    const auto v = static_cast<unsigned char>(c);
    out.push_back(digits[v >> 4]);
    out.push_back(digits[v & 15]);
  }
  return out;
}

// UTF-8 argv -> UTF-16 code units (BMP only is enough for the tests).
std::u16string ToU16(const std::string& utf8) {
  std::u16string out;
  for (size_t i = 0; i < utf8.size();) {
    const auto c = static_cast<unsigned char>(utf8[i]);
    uint32_t cp = c;
    size_t extra = 0;
    if (c >= 0xF0) {
      cp = c & 0x07;
      extra = 3;
    } else if (c >= 0xE0) {
      cp = c & 0x0F;
      extra = 2;
    } else if (c >= 0xC0) {
      cp = c & 0x1F;
      extra = 1;
    }
    for (size_t k = 1; k <= extra && i + k < utf8.size(); ++k) {
      cp = (cp << 6) | (static_cast<unsigned char>(utf8[i + k]) & 0x3F);
    }
    i += 1 + extra;
    if (cp >= 0x10000) {
      cp -= 0x10000;
      out.push_back(static_cast<char16_t>(0xD800 + (cp >> 10)));
      out.push_back(static_cast<char16_t>(0xDC00 + (cp & 0x3FF)));
    } else {
      out.push_back(static_cast<char16_t>(cp));
    }
  }
  return out;
}

int Usage() {
  std::fprintf(stderr, "bad arguments\n");
  return 64;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 2) return Usage();
  const std::string cmd = argv[1];

  if (cmd == "dib2bmp" && argc == 4) {
    const std::vector<uint8_t> dib = ReadFile(argv[2]);
    std::vector<uint8_t> bmp;
    if (!BuildBmpFromDib(dib.data(), dib.size(), &bmp)) return 2;
    WriteFile(argv[3], bmp);
    return 0;
  }
  if (cmd == "png" && argc == 3) {
    const std::vector<uint8_t> data = ReadFile(argv[2]);
    std::printf("%zu\n", PngStreamLength(data.data(), data.size()));
    return 0;
  }
  if (cmd == "drop" && argc == 3) {
    const std::vector<uint8_t> data = ReadFile(argv[2]);
    bool wide = false;
    std::vector<std::string> entries;
    if (!ParseDropFiles(data.data(), data.size(), &wide, &entries)) return 2;
    std::printf("wide=%d\n", wide ? 1 : 0);
    for (const std::string& entry : entries) {
      std::printf("%s\n", Hex(entry).c_str());
    }
    return 0;
  }
  if ((cmd == "drivepath" || cmd == "extension") && argc == 4) {
    const std::string mode = argv[2];
    const std::string utf8 = argv[3];
    if (cmd == "drivepath") {
      const bool ok = mode == "u16" ? IsLocalDrivePath(ToU16(utf8))
                                    : IsLocalDrivePath(utf8);
      std::printf("%d\n", ok ? 1 : 0);
    } else {
      const char* ext = mode == "u16" ? AllowedImageExtension(ToU16(utf8))
                                      : AllowedImageExtension(utf8);
      std::printf("%s\n", ext == nullptr ? "-" : ext);
    }
    return 0;
  }
  if (cmd == "flatten" && argc == 4) {
    std::vector<uint8_t> px = ReadFile(argv[2]);
    const bool changed = FlattenAlpha(&px);
    WriteFile(argv[3], px);
    std::printf("%d\n", changed ? 1 : 0);
    return 0;
  }
  if (cmd == "gray" && argc == 5) {
    std::vector<uint8_t> px = ReadFile(argv[3]);
    PrepareGray(&px, std::string(argv[2]) == "1");
    WriteFile(argv[4], px);
    return 0;
  }
  if (cmd == "pad" && argc == 8) {
    int32_t w = std::atoi(argv[2]);
    int32_t h = std::atoi(argv[3]);
    std::vector<uint8_t> px = ReadFile(argv[6]);
    PadGray(&px, &w, &h, std::atoi(argv[4]),
            static_cast<uint8_t>(std::atoi(argv[5])));
    WriteFile(argv[7], px);
    std::printf("%d %d\n", w, h);
    return 0;
  }
  if (cmd == "median" && argc == 3) {
    std::printf("%d\n", MedianLuma(ReadFile(argv[2])));
    return 0;
  }
  if (cmd == "translucent" && argc == 3) {
    std::printf("%d\n", HasTranslucentPixels(ReadFile(argv[2])) ? 1 : 0);
    return 0;
  }
  if (cmd == "fit" && argc == 5) {
    int32_t w = 0;
    int32_t h = 0;
    FitDimensions(std::atoi(argv[2]), std::atoi(argv[3]), std::atoi(argv[4]),
                  &w, &h);
    std::printf("%d %d\n", w, h);
    return 0;
  }
  if (cmd == "padamount" && argc == 5) {
    std::printf("%d\n", PadAmount(std::atoi(argv[2]), std::atoi(argv[3]),
                                  std::atoi(argv[4])));
    return 0;
  }
  if (cmd == "plan" && argc == 7) {
    const std::vector<OcrPlan> plans =
        PlanOcrAttempts(std::atoi(argv[2]), std::atoi(argv[3]),
                        std::atoi(argv[4]), std::atoi(argv[5]),
                        std::string(argv[6]) == "1");
    for (const OcrPlan& plan : plans) {
      std::printf("%d %d %d %s\n", plan.scale, plan.gray ? 1 : 0,
                  plan.invert ? 1 : 0, plan.name.c_str());
    }
    return 0;
  }
  if (cmd == "score" || cmd == "despace") {
    std::vector<std::string> lines;
    std::string line;
    while (std::getline(std::cin, line)) lines.push_back(line);
    if (cmd == "score") {
      const LinesScore s = ScoreLines(lines);
      std::printf("%d %d %d\n", s.score, s.has_email ? 1 : 0,
                  s.complete ? 1 : 0);
    } else {
      for (const std::string& l : lines) {
        std::printf("%s\n", RepairLetterSpacing(l).c_str());
      }
    }
    return 0;
  }
  if (cmd == "merge" && argc == 3) {
    // stdin: blocks separated by "---"; first line of a block is
    // "<score> <complete 0|1>", the rest are its lines.
    std::vector<OcrAttempt> attempts;
    std::string line;
    bool header = true;
    attempts.emplace_back();
    while (std::getline(std::cin, line)) {
      if (line == "---") {
        attempts.emplace_back();
        header = true;
        continue;
      }
      if (header) {
        int score = 0;
        int complete = 0;
        std::sscanf(line.c_str(), "%d %d", &score, &complete);
        attempts.back().score = score;
        attempts.back().complete = complete != 0;
        header = false;
      } else {
        attempts.back().lines.push_back(line);
      }
    }
    const auto best = static_cast<size_t>(std::atoi(argv[2]));
    if (best >= attempts.size()) return 2;
    for (const std::string& l : MergeAttemptLines(attempts, best)) {
      std::printf("%s\n", l.c_str());
    }
    return 0;
  }
  if (cmd == "lower") {
    std::string line;
    std::getline(std::cin, line);
    std::printf("%s\n", LowerAscii(line).c_str());
    return 0;
  }
  if (cmd == "blank") {
    std::string line;
    std::getline(std::cin, line);
    std::printf("%d\n", IsBlank(line) ? 1 : 0);
    return 0;
  }
  return Usage();
}
