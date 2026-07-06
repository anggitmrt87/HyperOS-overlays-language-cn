#!/bin/bash

set -e

if [ "$1" == "--local-aapt" ];then
    export LD_LIBRARY_PATH=.
    export PATH=.:$PATH
    shift
fi

script_dir="$(dirname "$(readlink -f -- "$0")")"
if [ "$#" -eq 1 ]; then
    if [ -d "$1" ];then
        makes="$(find "$1" -name Android.mk -exec readlink -f -- '{}' \;)"
    else
        makes="$(readlink -f -- "$1")"
    fi
else
    cd "$script_dir"
    makes="$(find "$PWD/.." -name Android.mk)"
fi

if ! command -v aapt2 > /dev/null;then
    export LD_LIBRARY_PATH=.
    export PATH=$PATH:.
fi

if ! command -v aapt2 > /dev/null; then
    echo "Please install aapt2 (apt install aapt2)"
    exit 1
fi

cd "$script_dir"

root_dir="$(cd "$script_dir/.." && pwd)"
overlay_mk="$root_dir/overlay.mk"

declare -a product_packages
declare -a vendor_packages

if [ -f "$overlay_mk" ]; then
    current_section=""
    while IFS= read -r line; do
        line="${line%\\}"
        line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [[ -z "$line" ]] && continue

        if [[ "$line" == "# product overlay" ]]; then
            current_section="product"
            continue
        elif [[ "$line" == "# vendor overlay" ]]; then
            current_section="vendor"
            continue
        fi

        [[ "$line" == \#* ]] && continue

        if [[ "$current_section" == "product" ]]; then
            product_packages+=("$line")
        elif [[ "$current_section" == "vendor" ]]; then
            vendor_packages+=("$line")
        fi
    done < "$overlay_mk"
else
    echo "Warning: overlay.mk not found, APKs will stay in build/"
fi

contains() {
    local e match="$1"
    shift
    for e; do [[ "$e" == "$match" ]] && return 0; done
    return 1
}

cleanup_values() {
    local res_dir="$1"
    echo "Cleaning @ references in values files under $res_dir"
    find "$res_dir/values"* -name "arrays.xml" -type f -print0 | while IFS= read -r -d '' file; do
        awk '
            BEGIN { in_block=0; block="" }
            /<array/ || /<string-array/ {
                in_block=1
                block=$0
                next
            }
            /<\/array>/ || /<\/string-array>/ {
                if (in_block) {
                    block = block "\n" $0
                    if (block !~ /@/) {
                        print block
                    }
                    in_block=0
                    block=""
                    next
                }
            }
            in_block {
                block = block "\n" $0
                next
            }
            !in_block {
                print
            }
        ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    done
}

build_with_aapt2() {
    local name="$1"
    local path="$2"

    local temp_android_data="$PWD/android_data_$$"
    mkdir -p "$temp_android_data"
    export ANDROID_DATA="$temp_android_data"

    local temp_res="$PWD/temp_res_$$"
    mkdir -p "$temp_res"
    cp -r "$path/res"/* "$temp_res/"

    cleanup_values "$temp_res"

    local compiled_dir="$PWD/compiled_$$"
    mkdir -p "$compiled_dir"

    echo "Compiling resources with aapt2..."
    find "$temp_res" -type f -print0 | while IFS= read -r -d '' file; do
        aapt2 compile -o "$compiled_dir" "$file" || return 1
    done

    echo "Linking resources with aapt2..."
    aapt2 link -o "${name}-unsigned.apk" \
        -I android.jar \
        --manifest "$path/AndroidManifest.xml" \
        $(find "$compiled_dir" -name "*.flat" -printf "-R %p ") \
        --auto-add-overlay \
        --no-resource-removal

    local ret=$?

    rm -rf "$temp_android_data" "$temp_res" "$compiled_dir"
    unset ANDROID_DATA
    return $ret
}

echo "$makes" | while read -r f; do
    name="$(sed -nE 's/LOCAL_PACKAGE_NAME.*:\=\s*(.*)/\1/p' "$f")"
    echo "Generating $name"

    path="$(dirname "$f")"

    if build_with_aapt2 "$name" "$path"; then
        echo "Successfully built with aapt2"
    else
        echo "Failed to build $name with aapt2"
        exit 1
    fi

    LD_LIBRARY_PATH=./signapk/ java -jar signapk/signapk.jar keys/platform.x509.pem keys/platform.pk8 "${name}-unsigned.apk" "${name}.apk"
    rm -f "${name}-unsigned.apk"

    if [ -f "$overlay_mk" ]; then
        if contains "$name" "${product_packages[@]}"; then
            target_dir="$root_dir/product/overlay"
        elif contains "$name" "${vendor_packages[@]}"; then
            target_dir="$root_dir/vendor/overlay"
        else
            target_dir="$root_dir/build"
        fi
        mkdir -p "$target_dir"
        mv "${name}.apk" "$target_dir/"
        echo "Moved ${name}.apk to $target_dir"
    fi
done
