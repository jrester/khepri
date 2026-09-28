# Shared container image pins for the tests, keyed by name. A test references
# `(import ./images.nix pkgs).nginx` instead of copy-pasting the digest/sha256,
# so a pin lives in one place and can't drift between tests.
pkgs: {
  nginx = pkgs.dockerTools.pullImage {
    imageName = "nginx";
    imageDigest = "sha256:0f04e4f646a3f14bf31d8bc8d885b6c951fdcf42589d06845f64d18aec6a3c4d";
    sha256 = "159z86nw6riirs9ix4zix7qawhfngl5fkx7ypmi6ib0sfayc8pw2";
    finalImageName = "nginx";
    finalImageTag = "latest";
  };

  postgres = pkgs.dockerTools.pullImage {
    imageName = "postgres";
    imageDigest = "sha256:7f29c02ba9eeff4de9a9f414d803faa0e6fe5e8d15ebe217e3e418c82e652b35";
    sha256 = "1zklv6y7xs7l4kcy4bbx8bg7mydrg6hna5g8in382mbjb4fi78gh";
    finalImageName = "postgres";
    finalImageTag = "17";
  };

  redis = pkgs.dockerTools.pullImage {
    imageName = "redis";
    imageDigest = "sha256:bd41d55aae1ecff61b2fafd0d66761223fe94a60373eb6bb781cfbb570a84079";
    sha256 = "0j8f8yxlqz99j38kb6sm1q7x5723mw6nprdjs5zdha3yki66ac9r";
    finalImageName = "redis";
    finalImageTag = "latest";
  };

  nextcloud = pkgs.dockerTools.pullImage {
    imageName = "nextcloud";
    imageDigest = "sha256:ff2cbaab14c85e587b5541e3aff4216a8a484e06424ebae661581937c0c8da0c";
    hash = "sha256-XDbwoTMubzgajpMIiGR5leeQEQYjS3sv0P6Cjkwk4mI=";
    finalImageName = "nextcloud";
    finalImageTag = "33.0.0-apache";
  };

  whoami = pkgs.dockerTools.pullImage {
    imageName = "traefik/whoami";
    imageDigest = "sha256:200689790a0a0ea48ca45992e0450bc26ccab5307375b41c84dfc4f2475937ab";
    hash = "sha256-Y6ZZJ9vgg8slPYe84kv46/VcbsrzD/UFVHcdmLMNrb4=";
    finalImageName = "traefik/whoami";
    finalImageTag = "v1.11";
  };
}
