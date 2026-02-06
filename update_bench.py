from pathlib import Path

# Find all matching directories
for output_dir in Path('.').glob('install-*/test/output'):
    parent = output_dir.parent  # eg. install-foo/test/
    bench_dir = parent / 'bench'
    
    # Check if bench_dir already exists
    if bench_dir.exists():
        print(f"Warning: {bench_dir} already exists. Skipping.")
        continue

    # Rename (move) output_dir to bench_dir
    output_dir.rename(bench_dir)
    print(f"Moved {output_dir} to {bench_dir}")
