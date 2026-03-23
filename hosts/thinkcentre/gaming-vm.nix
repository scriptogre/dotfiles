{ pkgs, ... }: {

  # IOMMU for GPU passthrough + split lock fix for Windows VM performance
  boot.kernelParams = [
    "intel_iommu=on"
    "iommu=pt"
    "split_lock_detect=off"
  ];

  # VFIO modules for GPU passthrough (loaded but don't auto-bind — hook script handles binding)
  boot.kernelModules = [ "vfio_pci" "vfio" "vfio_iommu_type1" ];

  # Libvirt/QEMU for Windows gaming VM with GPU passthrough
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
    };
  };

  # Libvirt hook: bind/unbind dGPU (RTX 3060 Ti) for VM passthrough
  # iGPU stays on host for GDM + Plex QuickSync
  environment.etc."libvirt/hooks/qemu" = {
    mode = "0755";
    text = ''
      #!/bin/sh
      GUEST_NAME="$1"
      HOOK_NAME="$2"
      STATE_NAME="$3"

      DGPU_PCI="0000:01:00.0"
      DGPU_AUDIO_PCI="0000:01:00.1"

      if [ "$GUEST_NAME" != "win11" ]; then
        exit 0
      fi

      bind_to_vfio() {
        local pci="$1"
        local current_driver="$2"
        if [ -n "$current_driver" ] && [ -e "/sys/bus/pci/drivers/$current_driver/$pci" ]; then
          echo "$pci" > "/sys/bus/pci/drivers/$current_driver/unbind"
        fi
        echo "vfio-pci" > "/sys/bus/pci/devices/$pci/driver_override"
        echo "$pci" > /sys/bus/pci/drivers/vfio-pci/bind 2>/dev/null || true
      }

      unbind_from_vfio() {
        local pci="$1"
        if [ -e "/sys/bus/pci/drivers/vfio-pci/$pci" ]; then
          echo "$pci" > /sys/bus/pci/drivers/vfio-pci/unbind
        fi
        echo "" > "/sys/bus/pci/devices/$pci/driver_override"
      }

      if [ "$HOOK_NAME" = "prepare" ] && [ "$STATE_NAME" = "begin" ]; then
        modprobe vfio-pci

        # Bind dGPU + audio to vfio-pci
        bind_to_vfio "$DGPU_PCI" "nouveau"
        bind_to_vfio "$DGPU_AUDIO_PCI" "snd_hda_intel"

      elif [ "$HOOK_NAME" = "release" ] && [ "$STATE_NAME" = "end" ]; then
        # Release dGPU from vfio-pci
        unbind_from_vfio "$DGPU_PCI"
        unbind_from_vfio "$DGPU_AUDIO_PCI"

        sleep 1

        # Rescan PCI — nouveau reclaims the dGPU
        echo 1 > /sys/bus/pci/rescan
      fi
    '';
  };

  # cockpit-machines plugin for VM management in Cockpit web UI
  environment.systemPackages = with pkgs; [
    cockpit-machines
  ];
}
