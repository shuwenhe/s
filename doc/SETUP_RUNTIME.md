# S Compiler Runtime Setup Guide

## Quick Setup (Recommended)

Run the setup script to compile and install S compiler with full runtime:

```bash
cd /Users/feifei/shuwen/train/s
bash setup_runtime.sh
```

## What This Does

1. **Verifies** all S compiler source files exist
2. **Compiles** S compiler from source (C files)
3. **Installs** to `.local/bin/s`
4. **Tests** the compiler with a simple program

## Manual Compilation (Alternative)

If you prefer to compile manually:

### For ARM64 (Apple Silicon M1/M2/M3):
```bash
cd /Users/feifei/shuwen/train/s
bash bin/build_s_arm64.sh
make run  # This installs to .local/bin
```

### For x86_64 (Intel Mac):
```bash
cd /Users/feifei/shuwen/train/s
bash bin/build_s_x86_64.sh
make run  # This installs to .local/bin
```

## Requirements

- **gcc** (usually already installed on macOS with Xcode Command Line Tools)
- **make** (comes with Xcode Command Line Tools)

To verify:
```bash
gcc --version
make --version
```

## Troubleshooting

### If gcc is not found:
```bash
xcode-select --install
```

### If compilation fails:
1. Check that all source files exist:
   ```bash
   ls -la src/cmd/compile/seed/runtime/*.c
   ```
2. Verify gcc is working:
   ```bash
   gcc -v
   ```
3. Check disk space:
   ```bash
   df -h /
   ```

## After Setup

Once compiled, S compiler will be at:
```bash
/Users/feifei/shuwen/train/s/.local/bin/s
```

Test it:
```bash
/Users/feifei/shuwen/train/s/.local/bin/s --version
```

Then run NeurX training:
```bash
cd /Users/feifei/shuwen/train/neurx
make train
```

## Expected Output

After successful setup, `make train` should:
1. ✅ Compile S source to IR
2. ✅ Generate binary from IR
3. ✅ Execute training and save checkpoints
