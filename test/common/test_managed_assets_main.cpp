// Entry point for the standalone `test_managed_assets` target only — the same
// test sources also compile into goalc-test, which brings its own main().

#include "common/util/FileUtil.h"

#include "gtest/gtest.h"

int main(int argc, char** argv) {
  file_util::setup_project_path(std::nullopt, /*skip_logs=*/true);
  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
