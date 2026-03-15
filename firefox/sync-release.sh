#!/usr/bin/env bash

set -euo pipefail

release_tag="${RELEASE_TAG:-firefox-tete009}"
remote_path="tete009:"
asset_pattern="${ASSET_PATTERN:-^firefox-.*\\.7z$}"
download_dir="${RUNNER_TEMP:-/tmp}/firefox-release-assets"

mkdir -p "$download_dir"

echo "Listing remote files from $remote_path"
remote_json="$(rclone lsjson "$remote_path" --files-only)"

mapfile -t candidate_assets < <(
  jq -r --arg pattern "$asset_pattern" '
    [.[] | select(.Name | test($pattern)) | .Name]
    | sort
    | .[]
  ' <<<"$remote_json"
)

if ((${#candidate_assets[@]} == 0)); then
  echo "No remote assets matched pattern: $asset_pattern"
  exit 0
fi

echo "Reading current assets from release $release_tag"
release_json="$(gh release view "$release_tag" --json assets)"

declare -A existing_assets=()
while IFS= read -r asset_name; do
  [[ -n "$asset_name" ]] || continue
  existing_assets["$asset_name"]=1
done < <(jq -r '.assets[].name' <<<"$release_json")

uploaded=0
for asset_name in "${candidate_assets[@]}"; do
  if [[ -n "${existing_assets[$asset_name]:-}" ]]; then
    echo "Skipping existing asset: $asset_name"
    continue
  fi

  echo "Downloading missing asset: $asset_name"
  rclone copyto "$remote_path/$asset_name" "$download_dir/$asset_name"

  echo "Uploading asset to release $release_tag: $asset_name"
  gh release upload "$release_tag" "$download_dir/$asset_name"
  uploaded=1
done

if ((uploaded == 0)); then
  echo "Release already contains every matching asset."
else
  echo "Release sync completed."
fi
