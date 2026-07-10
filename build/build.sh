#!/bin/bash
set -e

# ================================================================
#  FUNGSI LOG DENGAN WARNA & EMOJI
# ================================================================
if [ -t 1 ]; then
    # Warna hanya jika output ke terminal
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
fi

log_info()    { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✅${NC} $1"; }
log_warn()    { echo -e "${YELLOW}⚠️${NC} $1"; }
log_error()   { echo -e "${RED}❌${NC} $1"; }
log_step()    { echo -e "${CYAN}▶${NC} $1"; }
log_header()  { echo -e "\n${BOLD}${CYAN}⏱ [$(date +%H:%M:%S)]${NC} ${BOLD}$1${NC}"; }

# ================================================================
#  PENANGANAN ARGUMEN --local-aapt
# ================================================================
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

# ================================================================
#  CEK KETERSEDIAAN aapt2
# ================================================================
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
    log_warn "overlay.mk tidak ditemukan, APK akan tetap di build/"
fi

contains() {
    local e match="$1"
    shift
    for e; do [[ "$e" == "$match" ]] && return 0; done
    return 1
}

cleanup_values() {
    local res_dir="$1"
    log_info "Membersihkan referensi @ di file values di $res_dir"
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

    echo "   🛠  Mengompilasi resource dengan aapt2..."
    find "$temp_res" -type f -print0 | while IFS= read -r -d '' file; do
        aapt2 compile -o "$compiled_dir" "$file" || return 1
    done

    echo "   🔗 Melakukan linking..."
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

# ================================================================
#  MAIN LOOP DENGAN OUTPUT KEREN
# ================================================================
log_header "Memulai proses build overlay"

# Kumpulkan daftar file Android.mk ke dalam array
mapfile -t make_files <<< "$makes"
total_files=${#make_files[@]}

if [ "$total_files" -eq 0 ]; then
    log_error "Tidak ditemukan file Android.mk"
    exit 1
fi

log_info "Ditemukan $total_files file Android.mk:"
for f in "${make_files[@]}"; do
    echo "   • $f"
done

# Variabel untuk statistik
total_success=0
total_fail=0
start_time=$(date +%s)

counter=1
for f in "${make_files[@]}"; do
    name="$(sed -nE 's/LOCAL_PACKAGE_NAME.*:\=\s*(.*)/\1/p' "$f")"
    path="$(dirname "$f")"

    log_header "[$counter/$total_files] Membangun $name"
    log_info "📂 Sumber: $path"

    build_start=$(date +%s)
    if build_with_aapt2 "$name" "$path"; then
        build_end=$(date +%s)
        duration=$((build_end - build_start))
        log_success "Berhasil! (waktu: ${duration}s)"
        total_success=$((total_success + 1))
    else
        log_error "Gagal membangun $name"
        total_fail=$((total_fail + 1))
        exit 1
    fi

    # Tanda tangani APK
    log_info "✍️  Menandatangani APK..."
    LD_LIBRARY_PATH=./signapk/ java -jar signapk/signapk.jar keys/platform.x509.pem keys/platform.pk8 "${name}-unsigned.apk" "${name}.apk"
    rm -f "${name}-unsigned.apk"

    # Pindahkan ke direktori tujuan
    if [ -f "$overlay_mk" ]; then
        if contains "$name" "${product_packages[@]}"; then
            target_dir="$root_dir/product/overlay"
        elif contains "$name" "${vendor_packages[@]}"; then
            target_dir="$root_dir/vendor/overlay"
        else
            target_dir="$root_dir/build"
        fi
    else
        target_dir="$root_dir/build"
    fi

    mkdir -p "$target_dir"
    mv "${name}.apk" "$target_dir/"
    log_success "📂 Dipindahkan ke $target_dir/${name}.apk"

    counter=$((counter + 1))
done

# ================================================================
#  RINGKASAN AKHIR
# ================================================================
end_time=$(date +%s)
total_duration=$((end_time - start_time))

echo -e "\n────────────────────────────────────────────────"
echo -e "${BOLD}🏁  Selesai!${NC}"
echo -e "   ${GREEN}✅ Berhasil:${NC} $total_success"
echo -e "   ${RED}❌ Gagal  :${NC} $total_fail"
echo -e "   ⏱ Total waktu: ${total_duration} detik"
echo -e "────────────────────────────────────────────────"
