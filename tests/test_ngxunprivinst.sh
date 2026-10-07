#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET_SCRIPT="${REPO_DIR}/ngxunprivinst.sh"

PASSED=0
FAILED=0

assert_equals() {
  local expected="$1"
  local actual="$2"
  local test_name="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  [PASS] ${test_name}"
    PASSED=$((PASSED + 1))
  else
    echo "  [FAIL] ${test_name}"
    echo "    Expected: '${expected}'"
    echo "    Actual:   '${actual}'"
    FAILED=$((FAILED + 1))
  fi
}

assert_contains() {
  local substring="$1"
  local actual="$2"
  local test_name="$3"
  if echo "$actual" | grep -q -- "$substring"; then
    echo "  [PASS] ${test_name}"
    PASSED=$((PASSED + 1))
  else
    echo "  [FAIL] ${test_name}"
    echo "    Expected output to contain: '${substring}'"
    echo "    Actual output: '${actual}'"
    FAILED=$((FAILED + 1))
  fi
}

assert_exit_code() {
  local expected_code="$1"
  local actual_code="$2"
  local test_name="$3"
  if [ "$expected_code" -eq "$actual_code" ]; then
    echo "  [PASS] ${test_name}"
    PASSED=$((PASSED + 1))
  else
    echo "  [FAIL] ${test_name}"
    echo "    Expected exit code: ${expected_code}"
    echo "    Actual exit code:   ${actual_code}"
    FAILED=$((FAILED + 1))
  fi
}

echo "=================================================="
echo " Running ngxunprivinst.sh Test Suite"
echo "=================================================="

# Test 1: Usage output on no arguments
echo "Test Category: Argument Validation"
out=$("${TARGET_SCRIPT}" 2>&1 || true)
assert_contains "Usage: ./ngxunprivinst.sh" "$out" "No args displays usage"

# Test 2: Mandatory -c and -k for fetch/list
set +e
"${TARGET_SCRIPT}" fetch >/dev/null 2>&1
code=$?
set -e
assert_exit_code 1 $code "fetch fails without -c and -k"

set +e
"${TARGET_SCRIPT}" list >/dev/null 2>&1
code=$?
set -e
assert_exit_code 1 $code "list fails without -c and -k"

# Test 3: Mandatory -p for install/upgrade
set +e
"${TARGET_SCRIPT}" install dummy_pkg.deb >/dev/null 2>&1
code=$?
set -e
assert_exit_code 1 $code "install fails without -p"

# Test 4: Mandatory package files for install/upgrade
set +e
"${TARGET_SCRIPT}" install -p /tmp/test >/dev/null 2>&1
code=$?
set -e
assert_exit_code 1 $code "install fails without specified package files"

# Test 5: Mandatory -j (license jwt) for R33+ packages
set +e
"${TARGET_SCRIPT}" install -p /tmp/test nginx-plus_37.0.0-1~resolute_amd64.deb >/dev/null 2>&1
code=$?
set -e
assert_exit_code 1 $code "install fails for semver R37 package without -j license"

set +e
"${TARGET_SCRIPT}" install -p /tmp/test nginx-plus_33-1~jammy_amd64.deb >/dev/null 2>&1
code=$?
set -e
assert_exit_code 1 $code "install fails for legacy R33 package without -j license"

# Test 6: OS Release variable parsing (quotes & codename)
echo ""
echo "Test Category: OS Release & Quote Stripping"

TMP_TEST_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_TEST_DIR}"' EXIT

# Test parsing with quoted /etc/os-release
cat <<'EOF' > "${TMP_TEST_DIR}/os-release-ubuntu"
NAME="Ubuntu"
VERSION="26.04 LTS (Resolute)"
ID="ubuntu"
VERSION_CODENAME="resolute"
UBUNTU_CODENAME="resolute"
EOF

# Parse variables as script does
DISTRO=$(grep -E "^ID=" "${TMP_TEST_DIR}/os-release-ubuntu" | cut -d '=' -f2 | tr '[:upper:]' '[:lower:]' | tr -d '"')
RELEASE=$(grep -E "^VERSION_CODENAME=" "${TMP_TEST_DIR}/os-release-ubuntu" | cut -d '=' -f2 | tr -d '"')

assert_equals "ubuntu" "$DISTRO" "Ubuntu ID unquoted cleanly"
assert_equals "resolute" "$RELEASE" "Ubuntu VERSION_CODENAME unquoted cleanly"

# Test 7: Version regex matching logic for list()
echo ""
echo "Test Category: Package Version Regex Matching"

MOCK_HTML='
<a href="nginx-plus_33-1~jammy_amd64.deb">nginx-plus_33-1~jammy_amd64.deb</a>
<a href="nginx-plus_37.0.0-1~resolute_amd64.deb">nginx-plus_37.0.0-1~resolute_amd64.deb</a>
<a href="nginx-plus-dbg_37.0.0-1~resolute_amd64.deb">nginx-plus-dbg_37.0.0-1~resolute_amd64.deb</a>
<a href="nginx-plus-37.0.1-1.el9.ngx.x86_64.rpm">nginx-plus-37.0.1-1.el9.ngx.x86_64.rpm</a>
'

VERSIONS_DEB=$(echo "$MOCK_HTML" | grep -v -- '-dbg' | grep -E "nginx-plus[_-][0-9]+(\.[0-9]+)*-[0-9]+" | grep -F amd64 | grep -F resolute | grep -Eo '[0-9]+(\.[0-9]+)*-[0-9]+' | sort | uniq)
assert_contains "37.0.0-1" "$VERSIONS_DEB" "Debian semver package version matched"

VERSIONS_RPM=$(echo "$MOCK_HTML" | grep -v -- '-dbg' | grep -E "nginx-plus[_-][0-9]+(\.[0-9]+)*-[0-9]+" | grep -F x86_64 | grep -F el9 | grep -Eo '[0-9]+(\.[0-9]+)*-[0-9]+' | sort | uniq)
assert_contains "37.0.1-1" "$VERSIONS_RPM" "RPM semver package version matched"

# Test 8: TARGETVER major version integer calculation
echo ""
echo "Test Category: TARGETVER Integer Evaluation"

MOCK_VERSION_OUTPUT_LEGACY="nginx version: nginx/1.25.3 (nginx-plus-r33)"
MOCK_VERSION_OUTPUT_SEMVER="nginx version: nginx/1.27.4 (nginx-plus-r37.0.0)"

TARGETVER_LEGACY=$(echo "$MOCK_VERSION_OUTPUT_LEGACY" | cut -d '(' -f 2 | cut -d ')' -f 1 | cut -d'-' -f 3 | tr -d 'r' | cut -d'.' -f1)
TARGETVER_SEMVER=$(echo "$MOCK_VERSION_OUTPUT_SEMVER" | cut -d '(' -f 2 | cut -d ')' -f 1 | cut -d'-' -f 3 | tr -d 'r' | cut -d'.' -f1)

assert_equals "33" "$TARGETVER_LEGACY" "Legacy TARGETVER evaluates to integer 33"
assert_equals "37" "$TARGETVER_SEMVER" "Semver TARGETVER evaluates to integer 37"

# Test shell arithmetic comparison on semver major integer
if [ "$TARGETVER_SEMVER" -ge 33 ]; then code=0; else code=1; fi
assert_exit_code 0 "$code" "TARGETVER integer comparison [ 37 -ge 33 ] succeeds without syntax error"

# Test 9: End-to-End Installation with synthetic package
echo ""
echo "Test Category: End-to-End Installation Test"

E2E_DIR=$(mktemp -d)
E2E_PKG_BUILD="${E2E_DIR}/pkg-root"
E2E_INSTALL_TARGET="${E2E_DIR}/opt/nginx"
E2E_LICENSE="${E2E_DIR}/license.jwt"

echo "mock_jwt_token_secret" > "${E2E_LICENSE}"

mkdir -p "${E2E_PKG_BUILD}/usr/sbin"
mkdir -p "${E2E_PKG_BUILD}/etc/nginx/conf.d"
mkdir -p "${E2E_PKG_BUILD}/usr/share/nginx/html"

cat <<'EOF' > "${E2E_PKG_BUILD}/usr/sbin/nginx"
#!/bin/sh
if [ "$1" = "-v" ]; then
    echo "nginx version: nginx/1.27.4 (nginx-plus-r37.0.0)" >&2
    exit 0
fi
if [ "$1" = "-V" ]; then
    echo "nginx version: nginx/1.27.4 (nginx-plus-r37.0.0)" >&2
    echo "configure arguments: --prefix=/etc/nginx" >&2
    exit 0
fi
if [ "$1" = "-T" ]; then
    echo "# nginx config test ok"
    exit 0
fi
exit 0
EOF
chmod +x "${E2E_PKG_BUILD}/usr/sbin/nginx"

cat <<'EOF' > "${E2E_PKG_BUILD}/etc/nginx/nginx.conf"
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log notice;
pid /var/run/nginx.pid;
events { worker_connections 1024; }
http {
    access_log /var/log/nginx/access.log;
    include /etc/nginx/conf.d/*.conf;
}
EOF

cat <<'EOF' > "${E2E_PKG_BUILD}/etc/nginx/conf.d/default.conf"
server {
    listen 80;
    root /usr/share/nginx/html;
}
EOF

PKG_FILE=""
if command -v dpkg-deb >/dev/null 2>&1; then
  mkdir -p "${E2E_PKG_BUILD}/DEBIAN"
  cat <<'EOF' > "${E2E_PKG_BUILD}/DEBIAN/control"
Package: nginx-plus
Version: 37.0.0-1~resolute
Architecture: amd64
Maintainer: NGINX Test
Description: Dummy NGINX Plus package for testing
EOF
  dpkg-deb -b "${E2E_PKG_BUILD}" "${E2E_DIR}/nginx-plus_37.0.0-1~resolute_amd64.deb" >/dev/null 2>&1
  PKG_FILE="${E2E_DIR}/nginx-plus_37.0.0-1~resolute_amd64.deb"
elif command -v tar >/dev/null 2>&1; then
  (cd "${E2E_PKG_BUILD}" && tar -czf "${E2E_DIR}/nginx-plus-37.0.0-r1.apk" .)
  PKG_FILE="${E2E_DIR}/nginx-plus-37.0.0-r1.apk"
fi

if [ "$(uname -s)" = "Linux" ] && [ -n "${PKG_FILE}" ] && [ -f "${PKG_FILE}" ]; then
  set +e
  install_out=$("${TARGET_SCRIPT}" install -y -p "${E2E_INSTALL_TARGET}" -j "${E2E_LICENSE}" "${PKG_FILE}" 2>&1)
  install_code=$?
  set -e
  if [ "$install_code" -ne 0 ]; then
    echo "  [DEBUG] install_code=${install_code}"
    echo "  [DEBUG] install_out:"
    echo "${install_out}" | sed 's/^/    /'
    echo "  [DEBUG] ls -laR ${E2E_INSTALL_TARGET}:"
    ls -laR "${E2E_INSTALL_TARGET}" 2>&1 | sed 's/^/    /' || true
  fi

  if [ -x "${E2E_INSTALL_TARGET}/usr/sbin/nginx" ]; then
    assert_equals "0" "0" "E2E install unpacked nginx binary to prefix"
  else
    assert_equals "0" "1" "E2E install unpacked nginx binary to prefix"
  fi

  if [ -f "${E2E_INSTALL_TARGET}/etc/nginx/license.jwt" ]; then
    assert_equals "0" "0" "E2E install deployed license.jwt token"
  else
    assert_equals "0" "1" "E2E install deployed license.jwt token"
  fi

  if [ -f "${E2E_INSTALL_TARGET}/etc/nginx/nginx.conf" ] && grep -q "license_token ${E2E_INSTALL_TARGET}/etc/nginx/license.jwt" "${E2E_INSTALL_TARGET}/etc/nginx/nginx.conf"; then
    assert_equals "0" "0" "E2E install updated nginx.conf with unprivileged license_token directive"
  else
    assert_equals "0" "1" "E2E install updated nginx.conf with unprivileged license_token directive"
  fi
else
  echo "  [SKIP] E2E installation test (requires Linux container with package manager tools)"
fi

rm -rf "${E2E_DIR}"

# Test 10: Live Repository Integration Test (when secrets are provided)
echo ""
echo "Test Category: Live Repository & Package Test"

if [ "$(uname -s)" = "Linux" ] && \
   [ -n "${NGINX_REPO_CRT:-}" ] && [ -f "${NGINX_REPO_CRT}" ] && \
   [ -n "${NGINX_REPO_KEY:-}" ] && [ -f "${NGINX_REPO_KEY}" ] && \
   [ -n "${NGINX_LICENSE_JWT:-}" ] && [ -f "${NGINX_LICENSE_JWT}" ]; then

  echo "  Secret certificates detected on Linux. Running live pkgs.nginx.com fetch and install..."
  LIVE_DIR=$(mktemp -d)
  LIVE_PREFIX="${LIVE_DIR}/opt/nginx-live"

  # Run list
  list_out=$("${TARGET_SCRIPT}" list -c "${NGINX_REPO_CRT}" -k "${NGINX_REPO_KEY}" 2>&1 || true)
  if echo "$list_out" | grep -q "Versions available"; then
    assert_equals "0" "0" "Live repository version listing succeeded"
  else
    assert_equals "0" "1" "Live repository version listing succeeded"
  fi

  # Run fetch
  set +e
  fetch_out=$(cd "${LIVE_DIR}" && "${TARGET_SCRIPT}" fetch -c "${NGINX_REPO_CRT}" -k "${NGINX_REPO_KEY}" 2>&1)
  fetch_code=$?
  set -e

  DOWNLOADED_PKG=$(find "${LIVE_DIR}" -type f \( -name "nginx-plus_*.deb" -o -name "nginx-plus-*.rpm" -o -name "nginx-plus-*.apk" \) ! -name "*module*" | head -1)

  if [ -n "${DOWNLOADED_PKG}" ] && [ -f "${DOWNLOADED_PKG}" ]; then
    assert_equals "0" "0" "Live package fetch from pkgs.nginx.com succeeded"

    # Run install
    set +e
    live_install_out=$("${TARGET_SCRIPT}" install -y -p "${LIVE_PREFIX}" -j "${NGINX_LICENSE_JWT}" "${DOWNLOADED_PKG}" 2>&1)
    live_install_code=$?
    set -e
    if [ "$live_install_code" -ne 0 ]; then
      echo "  [DEBUG] live_install_code=${live_install_code}"
      echo "  [DEBUG] live_install_out:"
      echo "${live_install_out}" | sed 's/^/    /'
      echo "  [DEBUG] ls -laR ${LIVE_PREFIX}:"
      ls -laR "${LIVE_PREFIX}" 2>&1 | sed 's/^/    /' || true
    fi

    if [ -x "${LIVE_PREFIX}/usr/sbin/nginx" ]; then
      assert_equals "0" "0" "Live NGINX Plus package extracted successfully"
    else
      assert_equals "0" "1" "Live NGINX Plus package extracted successfully"
    fi
  else
    echo "  [DEBUG fetch] fetch_code=${fetch_code}"
    echo "  [DEBUG fetch] fetch_out:"
    echo "${fetch_out}" | sed 's/^/    /'
    echo "  [DEBUG fetch] ls -laR ${LIVE_DIR}:"
    ls -laR "${LIVE_DIR}" 2>&1 | sed 's/^/    /' || true
    assert_equals "0" "1" "Live package fetch from pkgs.nginx.com succeeded"
  fi

  rm -rf "${LIVE_DIR}"
else
  echo "  [SKIP] Live repository test (requires Linux OS/container with secrets provided)"
fi

echo ""
echo "=================================================="
echo " Test Results: ${PASSED} Passed, ${FAILED} Failed"
echo "=================================================="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
