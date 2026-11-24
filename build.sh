#!/bin/bash

# Compiling Setting
export DEVICE=$1
export MODE=$2
export ANDROID_BUILD_TOP=$(pwd)
export AIK_DIR=${ANDROID_BUILD_TOP}/prebuilts/AIK
export OUT_DIR=${ANDROID_BUILD_TOP}/out

# Import KernelSU-Next driver
if [ "${MODE}" == 'ksun' ]; then
    curl -LSs "https://raw.githubusercontent.com/huynhbaman/FinaSU---Non-GKI/refs/heads/Non-GKI/kernel/setup.sh" | bash -s Non-GKI

    # FinaSU currently defines syscall_fn_t for x86/RISC-V only.  The Exynos
    # kernel is AArch64, so define the ARM64 function-pointer type explicitly.
    python3 - <<'PY'
from pathlib import Path

header = Path("drivers/kernelsu/hook/syscall_hook.h")
text = header.read_text()
if "#elif defined(__aarch64__)" not in text:
    text = text.replace(
        "#elif defined(__riscv)\n",
        "#elif defined(__aarch64__)\n"
        "typedef long (*syscall_fn_t)(const struct pt_regs *);\n"
        "#elif defined(__riscv)\n",
    )
header.write_text(text)

init = Path("drivers/kernelsu/core/init.c")
text = init.read_text()
text = "\n".join(line for line in text.splitlines() if "MODULE_IMPORT_NS(" not in line)
text += "\n"
init.write_text(text)

# Samsung/old out-of-tree kernels do not support statement-expression
# ratelimit macros consistently with recent Clang.
umount = Path("drivers/kernelsu/feature/kernel_umount.c")
if umount.exists():
    text = umount.read_text()
    text = text.replace("pr_info_ratelimited(", "pr_info(")
    text = text.replace("pr_warn_ratelimited(", "pr_warn(")
    text = text.replace("pr_err_ratelimited(", "pr_err(")
    umount.write_text(text)

# FinaSU uses C11 static_assert(), while this old Samsung kernel build can
# expose no compatible static_assert macro.
kernelsu = Path("drivers/kernelsu")
for source in kernelsu.rglob("*"):
    if source.is_file() and source.suffix in (".c", ".h"):
        text = source.read_text()
        updated = text.replace("static_assert(", "_Static_assert(")
        updated = updated.replace("__poll_t", "unsigned int")
        if updated != text:
            source.write_text(updated)

# Exynos9820 uses Linux 4.14.  FinaSU's runtime LSM and file-wrapper
# implementations target newer kernels.  Replace unsupported implementations.
lsm_hook = kernelsu / "hook" / "lsm_hook.c"
lsm_hook.write_text(r'''#include <linux/errno.h>
#include <linux/printk.h>
#include "lsm_hook.h"

int ksu_lsm_hook(struct ksu_lsm_hook *hook)
{
	pr_warn_once("FinaSU: LSM runtime hooking is unsupported on this kernel\n");
	return -EOPNOTSUPP;
}

void ksu_lsm_unhook(struct ksu_lsm_hook *hook)
{
}

int ksu_register_lsm_hook(struct ksu_lsm_hook *hook)
{
	return ksu_lsm_hook(hook);
}

void ksu_unregister_lsm_hook(struct ksu_lsm_hook *hook)
{
	ksu_lsm_unhook(hook);
}

void ksu_lsm_hook_init(void)
{
}

void ksu_lsm_hook_exit(void)
{
}
''')

file_wrapper = kernelsu / "infra" / "file_wrapper.c"
file_wrapper.write_text(r'''#include <linux/errno.h>
#include <linux/printk.h>
#include "infra/file_wrapper.h"

int ksu_install_file_wrapper(int fd)
{
	pr_warn_once("FinaSU: file wrapper is unsupported on this kernel\n");
	return -EOPNOTSUPP;
}

void ksu_file_wrapper_init(void)
{
}
''')

# Linux 4.14 predates __poll_t and the EPOLL* compatibility constants.
event_header = kernelsu / "infra" / "event_queue.h"
text = event_header.read_text()
compat = r'''#ifndef __KSU_LINUX_414_POLL_COMPAT
#define __KSU_LINUX_414_POLL_COMPAT
#ifndef EPOLLIN
#define EPOLLIN POLLIN
#endif
#ifndef EPOLLRDNORM
#define EPOLLRDNORM POLLRDNORM
#endif
#ifndef EPOLLHUP
#define EPOLLHUP POLLHUP
#endif
#ifndef EPOLLERR
#define EPOLLERR POLLERR
#endif
#ifndef EPOLLRDHUP
#define EPOLLRDHUP POLLHUP
#endif
#endif

'''
if "__KSU_LINUX_414_POLL_COMPAT" not in text:
    marker = "#include <linux/wait.h>\n"
    text = text.replace(marker, marker + "\n" + compat)
    event_header.write_text(text)

# Linux 4.14 lacks the newer SECCOMP_ARCH_NATIVE_NR cache API used by
# FinaSU. Stub the cache operations because syscall hooking remains active.
seccomp_cache = kernelsu / "infra" / "seccomp_cache.c"
seccomp_cache.write_text(r'''#include <linux/seccomp.h>
#include "infra/seccomp_cache.h"

void ksu_seccomp_clear_cache(struct seccomp_filter *filter, int nr)
{
}

void ksu_seccomp_allow_cache(struct seccomp_filter *filter, int nr)
{
}
''')

# Linux 4.14 uses <linux/mount.h>; newer FinaSU sources use the UAPI path.
mount_ns = kernelsu / "infra" / "su_mount_ns.c"
if mount_ns.exists():
    text = mount_ns.read_text()
    text = text.replace("#include <uapi/linux/mount.h>", "#include <linux/mount.h>")
    mount_ns.write_text(text)

# Linux 4.x uses asm/pgtable.h rather than the newer linux/pgtable.h.
sucompat = Path("drivers/kernelsu/feature/sucompat.c")
if sucompat.exists():
    text = sucompat.read_text()
    text = text.replace("#include <linux/pgtable.h>", "#include <asm/pgtable.h>")
    sucompat.write_text(text)
PY
fi

# Define specific variables
case ${DEVICE} in
beyond0lte)
    BOARD=SRPRI28A016KU
    SOC=exynos9820
    TZDEV=new
;;
beyond0lteks)
    BOARD=SRPRI28C007KU
    SOC=exynos9820
    TZDEV=new
;;
beyond1lte)
    BOARD=SRPRI28B016KU
    SOC=exynos9820
    TZDEV=new
;;
beyond1lteks)
    BOARD=SRPRI28D007KU
    SOC=exynos9820
    TZDEV=new
;;
beyond2lte)
    BOARD=SRPRI17C016KU
    SOC=exynos9820
    TZDEV=new
;;
beyond2lteks)
    BOARD=SRPRI28C007KU
    SOC=exynos9820
    TZDEV=new
;;
beyondx)
    BOARD=SRPSC04B014KU
    SOC=exynos9820
    TZDEV=new
;;
beyondxks)
    BOARD=SRPRK21D014KU
    SOC=exynos9820
    TZDEV=new
;;
d1)
    BOARD=SRPSD26A012KU
    SOC=exynos9825
    TZDEV=old
;;
d1xks)
    BOARD=SRPSD23A002KU
    SOC=exynos9825
    TZDEV=new
;;
d2s)
    BOARD=SRPSC14B009KU
    SOC=exynos9825
    TZDEV=old
;;
d2x)
    BOARD=SRPSC14C009KU
    SOC=exynos9825
    TZDEV=old
;;
d2xks)
    BOARD=SRPSD23C002KU
    SOC=exynos9825
    TZDEV=new
;;
*)
    exit
;;
esac
echo -n "${BOARD}" > "${AIK_DIR}/split_img/boot.img-board"

# Add Specific Device DEFCONFIG
echo -e "\nCONFIG_MODEL_${DEVICE^^}=y" >> "${ANDROID_BUILD_TOP}/arch/arm64/configs/${SOC}.config"

# Setting tzdev drvier
rm -rf ${ANDROID_BUILD_TOP}/drivers/misc/tzdev
cp -ar ${ANDROID_BUILD_TOP}/prebuilts/tzdev/tzdev_${TZDEV} ${ANDROID_BUILD_TOP}/drivers/misc/tzdev

# OEM Setting
export ARCH=arm64
export PLATFORM_VERSION=12
export ANDROID_MAJOR_VERSION=s

# Setting toolchain
TOOLCHAIN_URL="https://github.com/GoRhanHee/exynos9820_toolchain/releases/download/toolchain/toolchain.tar.xz"
TOOLCHAIN_FILE=$(basename "$TOOLCHAIN_URL")
if [ ! -f "$TOOLCHAIN_FILE" ]; then
    wget -q --show-progress -O "$TOOLCHAIN_FILE" "$TOOLCHAIN_URL"
fi
tar -xf "$TOOLCHAIN_FILE" && rm "$TOOLCHAIN_FILE"

# Cooking Kernel Source
MAKE_ARGS="
ARCH=arm64 \
-j16 \
O=out
"

DEFCONFIG="exynos9820-${DEVICE}_defconfig ${SOC}.config"

if [ "${MODE}" == "ksun" ]; then
    CONFIGS="${DEFCONFIG} kernelsu.config"
else
    CONFIGS="${DEFCONFIG}"
fi

make ${MAKE_ARGS} ${CONFIGS} || exit 1
make ${MAKE_ARGS} || exit 1

# Cooking Ramdisk
cp ${ANDROID_BUILD_TOP}/prebuilts/ramdisk_prop/${DEVICE}.prop ${AIK_DIR}/ramdisk/system/etc/ramdisk/build.prop
cd ${AIK_DIR}/ramdisk
find . | cpio -o -H newc | gzip > ../split_img/boot.img-ramdisk.cpio.gz

cd ${ANDROID_BUILD_TOP}

# Cooking boot.img
cp ${OUT_DIR}/arch/arm64/boot/Image ${AIK_DIR}/split_img/boot.img-kernel
cd ${AIK_DIR} && ./repackimg.sh
cd ${ANDROID_BUILD_TOP}
mv ${AIK_DIR}/image-new.img ${ANDROID_BUILD_TOP}/prebuilts/boot.img

# Cooking dt.img
./prebuilts/mkdtimg cfg_create prebuilts/dt.img prebuilts/dtconfigs/${SOC}.cfg -d ${OUT_DIR}/arch/arm64/boot/dts/exynos

# Cooking dtbo.img
./prebuilts/mkdtimg cfg_create prebuilts/dtbo.img prebuilts/dtconfigs/${DEVICE}.cfg -d ${OUT_DIR}/arch/arm64/boot/dts/samsung

# Copying patched vbmeta.img
cp ${ANDROID_BUILD_TOP}/prebuilts/vbmeta/${DEVICE}.img ${ANDROID_BUILD_TOP}/prebuilts/vbmeta.img

# Cooking flashable tar file
cd ${ANDROID_BUILD_TOP}/prebuilts
zip -r GoRhanHee_Kernel_for_${DEVICE}_${MODE}.zip META-INF boot.img dt.img dtbo.img
