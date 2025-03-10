{
  lib,
  stdenv,
  nodejs_20,
  fetchFromGitHub,
  pnpm_9,
  nix-update-script,
  typescript,
  makeWrapper,
  rsync,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "logto";
  version = "1.25.0";

  src = fetchFromGitHub {
    owner = "logto-io";
    repo = finalAttrs.pname;
    rev = "v${finalAttrs.version}";
    hash = "sha256-+DG7/wjyWwZlkn3WdqpAYNlhCpbV5CMy2pANBpIQbQA=";
  };

  nativeBuildInputs = [
    nodejs_20
    pnpm_9.configHook
    typescript
    makeWrapper
    rsync
  ];

  pnpmDeps = pnpm_9.fetchDeps {
    inherit (finalAttrs) pname version src;
    hash = "sha256-Bf4phUmui0YSRdo+ELnKgz71lwn1bT2usi5JUpXo3FE=";
  };

  passthru = {
    updateScript = nix-update-script { };
  };

  buildPhase = ''
    runHook preBuild

    pnpm i
    pnpm -r build
    pnpm cli connector link
    env NODE_ENV=production pnpm i

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir $out
    mkdir $out/share
    mkdir $out/bin
    cp -r . $out/share/logto

    makeWrapper ${pnpm_9}/bin/pnpm $out/bin/logto \
      --chdir ${builtins.placeholder "out"}/share/logto \
      --add-flags start \
      --set-default NODE_ENV production \
      --prefix PATH : ${
        lib.makeBinPath [
          nodejs_20
          pnpm_9
        ]
      }

    runHook postInstall
  '';

  meta = {
    description = "An identity and access management (IAM) infrastructure with authentication, authorization, MFA, SSO, user management, and multi-tenancy features. Supports OAuth 2.0, OIDC, and SAML. No framework restrictions.";
    homepage = "https://logto.io/";
    license = lib.licenses.mpl20;
    maintainers = with lib.maintainers; [ benaryorg ];
  };
})
