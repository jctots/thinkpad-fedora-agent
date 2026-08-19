Name:           bitwarden-polkit-policy
Version:        1
Release:        1%{?dist}
Summary:        Polkit policy for Bitwarden desktop (Flatpak) biometric unlock
License:        GPL-3.0-or-later
BuildArch:      noarch
Source0:        com.bitwarden.Bitwarden.policy

%description
Installs the polkit action definition Bitwarden desktop (Flatpak build)
needs for system-authentication / fingerprint unlock, per
https://bitwarden.com/help/biometrics/. Not shipped by the Flatpak itself
since polkit only reads action files from /usr/share/polkit-1/actions on
the host, which the Flatpak sandbox cannot write to.

%install
mkdir -p %{buildroot}%{_datadir}/polkit-1/actions
install -m 0644 %{SOURCE0} %{buildroot}%{_datadir}/polkit-1/actions/com.bitwarden.Bitwarden.policy

%files
%{_datadir}/polkit-1/actions/com.bitwarden.Bitwarden.policy

%changelog
* Sun Aug 16 2026 maintainer <maintainer@example.com> - 1-1
- Initial package
