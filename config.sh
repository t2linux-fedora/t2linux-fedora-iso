#!/bin/bash

set -euxo pipefail

#======================================
# Functions...
#--------------------------------------
test -f /.kconfig && . /.kconfig
test -f /.profile && . /.profile

#======================================
# Greeting...
#--------------------------------------
echo "Configure image: [$kiwi_iname]-[$kiwi_profiles]..."

#======================================
# Set SELinux booleans
#--------------------------------------
if [[ "$kiwi_profiles" != *"Container"* ]]; then
	## Fixes KDE Plasma, see rhbz#2058657
	setsebool -P selinuxuser_execmod 1
fi

#======================================
# Clear machine specific configuration
#--------------------------------------
## Clear machine-id on pre generated images
rm -f /etc/machine-id
echo 'uninitialized' > /etc/machine-id
## remove random seed, the newly installed instance should make its own
rm -f /var/lib/systemd/random-seed

#======================================
# Configure grub correctly
#--------------------------------------
if [[ "$kiwi_profiles" != *"Container"* ]]; then
	## Works around issues with grub-bls
	## See: https://github.com/OSInside/kiwi/issues/2198
	echo "GRUB_DEFAULT=saved" >> /etc/default/grub
	## Disable submenus to match Fedora
	echo "GRUB_DISABLE_SUBMENU=true" >> /etc/default/grub
	## Disable recovery entries to match Fedora
	echo "GRUB_DISABLE_RECOVERY=true" >> /etc/default/grub
fi

#======================================
# Delete & lock the root user password
#--------------------------------------
if [[ "$kiwi_profiles" == *"Cloud"* ]] || [[ "$kiwi_profiles" == *"Live"* ]]; then
	passwd -d root
	passwd -l root
fi

#======================================
# Setup default services
#--------------------------------------

if [[ "$kiwi_profiles" == *"Live"* ]]; then
	## Configure livesys session
	if [[ "$kiwi_profiles" == *"GNOME"* ]]; then
		echo 'livesys_session="gnome"' > /etc/sysconfig/livesys
	fi
	if [[ "$kiwi_profiles" == *"KDE"* ]]; then
		echo 'livesys_session="kde"' > /etc/sysconfig/livesys
	fi
	if [[ "$kiwi_profiles" == *"Budgie"* ]]; then
		echo 'livesys_session="budgie"' > /etc/sysconfig/livesys
	fi
	if [[ "$kiwi_profiles" == *"Cinnamon"* ]]; then
		echo 'livesys_session="cinnamon"' > /etc/sysconfig/livesys
	fi
	if [[ "$kiwi_profiles" == *"i3"* ]]; then
		echo 'livesys_session="i3"' > /etc/sysconfig/livesys
	fi
	if [[ "$kiwi_profiles" == *"LXDE"* ]]; then
		echo 'livesys_session="lxde"' > /etc/sysconfig/livesys
	fi
	if [[ "$kiwi_profiles" == *"LXQt"* ]]; then
		echo 'livesys_session="lxqt"' > /etc/sysconfig/livesys
	fi
	if [[ "$kiwi_profiles" == *"MATE_Compiz"* ]]; then
		echo 'livesys_session="mate"' > /etc/sysconfig/livesys
	fi
	if [[ "$kiwi_profiles" == *"Sway"* ]]; then
		echo 'livesys_session="sway"' > /etc/sysconfig/livesys
	fi
	if [[ "$kiwi_profiles" == *"SoaS"* ]]; then
		echo 'livesys_session="soas"' > /etc/sysconfig/livesys
	fi
	if [[ "$kiwi_profiles" == *"Xfce"* ]]; then
		echo 'livesys_session="xfce"' > /etc/sysconfig/livesys
	fi
fi

#======================================
# Setup default target
#--------------------------------------
if [[ "$kiwi_profiles" != *"Container"* ]]; then
	if [[ "$kiwi_profiles" == *"Desktop"* ]]; then
		systemctl set-default graphical.target
	else
		systemctl set-default multi-user.target
	fi
fi

#======================================
# Setup default customizations
#--------------------------------------

if [[ "$kiwi_profiles" == *"Azure"* ]]; then
cat > /etc/ssh/sshd_config.d/50-client-alive-interval.conf << EOF
ClientAliveInterval 120
EOF

cat >> /etc/chrony.conf << EOF
# Azure's virtual time source:
# https://docs.microsoft.com/en-us/azure/virtual-machines/linux/time-sync#check-for-ptp-clock-source
refclock PHC /dev/ptp_hyperv poll 3 dpoll -2 offset 0
EOF

# Support Azure's accelerated networking feature; without this the network fails
# to come up. It may need adjustments for additional drivers in the future.
cat > /etc/NetworkManager/conf.d/99-azure-unmanaged-devices.conf << EOF
# Ignore SR-IOV interface on Azure, since it's transparently bonded
# to the synthetic interface
[keyfile]
unmanaged-devices=driver:mlx4_core;driver:mlx5_core
EOF
fi

if [[ "$kiwi_profiles" == *"GCE"* ]]; then
cat <<EOF > /etc/NetworkManager/conf.d/gcp-mtu.conf
# In GCP it is recommended to use 1460 as the MTU.
# Set it to 1460 for all connections.
# https://cloud.google.com/network-connectivity/docs/vpn/concepts/mtu-considerations
[connection]
ethernet.mtu = 1460
EOF
fi

if [[ "$kiwi_profiles" == *"Vagrant"* ]]; then
sed -e 's/.*UseDNS.*/UseDNS no/' -i /etc/ssh/sshd_config
mkdir -m 0700 -p ~vagrant/.ssh
cat > ~vagrant/.ssh/authorized_keys << EOKEYS
ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key
EOKEYS
chmod 600 ~vagrant/.ssh/authorized_keys
chown -R vagrant:vagrant ~vagrant/.ssh/

cat > /etc/sudoers.d/vagrant << EOSUDOER
## Ensure the vagrant user always can use sudo
Defaults:vagrant !requiretty
vagrant ALL=(ALL) NOPASSWD: ALL
EOSUDOER
chmod 600 /etc/sudoers.d/vagrant

cat > /etc/ssh/sshd_config.d/10-vagrant-insecure-rsa-key.conf <<EOF
# For now the vagrant insecure key is an rsa key
# https://github.com/hashicorp/vagrant/issues/11783
PubkeyAcceptedKeyTypes=+ssh-rsa
EOF

# Further suggestion from @purpleidea (James Shubin) - extend key to root users as well
mkdir -m 0700 -p /root/.ssh
cp /home/vagrant/.ssh/authorized_keys /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
chown -R root:root /root/.ssh
fi

if [[ "$kiwi_profiles" == *"Container"* ]]; then
	# Set install langs macro so that new rpms that get installed will
	# only install langs that we limit it to.
	LANG="en_US"
	echo "%_install_langs $LANG" > /etc/rpm/macros.image-language-conf

	# https://bugzilla.redhat.com/show_bug.cgi?id=1727489
	echo 'LANG="C.UTF-8"' >  /etc/locale.conf

	# https://bugzilla.redhat.com/show_bug.cgi?id=1400682
	echo "Import RPM GPG key"
	releasever=$(rpm --eval '%{?fedora}')

	# When building ELN containers, we don't have the %{fedora} macro
	if [ -z $releasever ]; then
		releasever=eln
	fi

	rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-$releasever-primary

	echo "# fstab intentionally empty for containers" > /etc/fstab

	# Remove machine-id on pre generated images
	rm -f /etc/machine-id
	touch /etc/machine-id

	echo "# resolv placeholder" > /etc/resolv.conf
	chmod 644 /etc/resolv.conf

	# Remove extraneous files
	rm -rf /tmp/*

	# https://pagure.io/atomic-wg/issue/308
	printf "tsflags=nodocs\n" >>/etc/dnf/dnf.conf

	if [[ "$kiwi_profiles" == *"Base-Generic-Minimal"* ]]; then
		# remove some random help txt files
		rm -fv /usr/share/gnupg/help*.txt

		# Pruning random things
		rm /usr/lib/rpm/rpm.daily
		rm -rfv /usr/lib64/nss/unsupported-tools/  # unsupported

		# Statically linked crap
		rm -fv /usr/sbin/{glibc_post_upgrade.x86_64,sln}
		ln /usr/bin/ln usr/sbin/sln

		# Remove some dnf info
		rm -rfv /var/lib/dnf

		# don't need icons
		rm -rfv /usr/share/icons/*

		#some random not-that-useful binaries
		rm -fv /usr/bin/pinky

		# we lose presets by removing /usr/lib/systemd but we do not care
		rm -rfv /usr/lib/systemd
	fi
	if [[ "$kiwi_profiles" == *"Toolbox"* ]]; then
		# Remove macros.image-language-conf file
		rm -f /etc/rpm/macros.image-language-conf

		# Remove 'tsflags=nodocs' line from dnf.conf
		sed -i '/tsflags=nodocs/d' /etc/dnf/dnf.conf
	fi
fi

if [[ "$kiwi_profiles" == *"SoaS"* ]]; then
# Get proper release naming in the control panel
cat >> /boot/olpc_build << EOF
Sugar on a Stick
EOF
cat /etc/fedora-release >> /boot/olpc_build

# Rebuild initrd for Sugar boot screen -- TODO: Switch to kiwi declarative stanza
KERNEL_VERSION=$(rpm -q kernel --qf '%{version}-%{release}.%{arch}\n')
/usr/sbin/plymouth-set-default-theme sugar
sed -i -r 's/(omit_dracutmodules\+\=.*) plymouth (.*)/\1 \2/' /etc/dracut.conf.d/99-liveos.conf
dracut --force-add plymouth -N -f /boot/initramfs-$KERNEL_VERSION.img $KERNEL_VERSION

# Note that running rpm recreates the rpm db files which aren't needed or wanted
rm -f /var/lib/rpm/__db*

cat > /etc/sysconfig/desktop <<EOF
PREFERRED=/usr/bin/sugar
DISPLAYMANAGER=/usr/sbin/lightdm
EOF

# set up lightdm autologin
sed -i 's/^#autologin-user=.*/autologin-user=liveuser/' /etc/lightdm/lightdm.conf
sed -i 's/^#autologin-user-timeout=.*/autologin-user-timeout=0/' /etc/lightdm/lightdm.conf

# Don't use the default system user (in SoaS liveuser) as nick name
# Disable the logout menu item in Sugar
# Enable Sugar power management
cat >/usr/share/glib-2.0/schemas/sugar.soas.gschema.override <<EOF
[org.sugarlabs.user]
default-nick='disabled'

[org.sugarlabs]
show-logout=false

[org.sugarlabs.power]
automatic=true
EOF

/usr/bin/glib-compile-schemas /usr/share/glib-2.0/schemas
fi

exit 0
