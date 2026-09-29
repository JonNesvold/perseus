{ pkgs, lib, userConfig, config, ... }:
{
  networking.wireguard.enable = true;
  systemd.tmpfiles.rules = [
    "L+ /etc/wireguard/mullvad.conf 0600 root systemd-network - ${config.sops.secrets.mullvad-conf.path}"
  ];
  networking.wg-quick.interfaces.mullvad = {
    configFile = "/etc/wireguard/mullvad.conf";
    # postUp is NOT used here — wg-quick ignores it when configFile is set.
    # Routing rules live in ExecStartPost below, which always fires.
    autostart = true;
  };
  systemd.services.wg-quick-mullvad = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig.ExecStartPost = let
      script = pkgs.writeShellScript "mullvad-post-up" ''
        set -eu
        ${pkgs.procps}/bin/sysctl -w net.ipv4.conf.all.src_valid_mark=1
        # wg-quick adds its two rules without a priority, so where they land depends
        # on boot order. Pin them below Tailscale's 5210 so Tailscale's own
        # encrypted traffic always leaves through Mullvad.
        ${pkgs.iproute2}/bin/ip rule del not fwmark 0xca6c table 51820
        ${pkgs.iproute2}/bin/ip rule add not fwmark 0xca6c table 51820 priority 5001
        ${pkgs.iproute2}/bin/ip rule del table main suppress_prefixlength 0
        ${pkgs.iproute2}/bin/ip rule add table main suppress_prefixlength 0 priority 5000
        echo "mullvad-post-up: rules pinned at 5000/5001"
      '';
    in [ "+${script}" ];
  };
  # wg-quick adds its rules without a priority, and the kernel slots such a rule
  # directly below the lowest existing one, so no fixed priority stays ahead of
  # Mullvad's catch-all (not fwmark 0xca6c -> lookup 51820). What wg-quick does
  # guarantee is that its `lookup main suppress_prefixlength 0` rule sits right
  # above that catch-all, and it routes anything in main more specific than the
  # default. So the tailnet CIDRs live in main, bound to tailscale0's lifetime.
  systemd.services.tailnet-main-route = {
    description = "Route tailnet CIDRs via tailscale0 in the main table";
    bindsTo = [ "sys-subsystem-net-devices-tailscale0.device" ];
    after = [ "sys-subsystem-net-devices-tailscale0.device" ];
    wantedBy = [ "sys-subsystem-net-devices-tailscale0.device" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = let
        script = pkgs.writeShellScript "tailnet-main-route" ''
          set -eu
          for cidr in 100.64.0.0/10 192.0.0.0/24; do
            ${pkgs.iproute2}/bin/ip route replace "$cidr" dev tailscale0
            echo "tailnet-main-route: $cidr -> tailscale0 (main)"
          done
        '';
      in "${script}";
    };
  };
  environment.systemPackages = with pkgs; [
    wireguard-tools
    (writeShellScriptBin "mullvad-toggle" ''
      if systemctl is-active --quiet wg-quick-mullvad; then
        sudo systemctl stop wg-quick-mullvad
        echo "VPN disconnected"
      else
        sudo systemctl start wg-quick-mullvad
        echo "VPN connected"
      fi
    '')
    (writeShellScriptBin "mullvad-status" ''
      if systemctl is-active --quiet wg-quick-mullvad; then
        echo "Connected"
      else
        echo "Disconnected"
      fi
    '')
  ];
}
