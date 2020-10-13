package bake

command: {
  server: #Dubo & {
    target: "server"
    args: {
      BUILD_TITLE: "Rudder Server"
      BUILD_DESCRIPTION: "A dubo image for Rudder based on \(args.DEBOOTSTRAP_SUITE) (\(args.DEBOOTSTRAP_DATE))"
    }
    // XXX seems like ppc64le makes qemu segfault in some occasions (build-all)?
    platforms: [
      AMD64,
      ARM64,
      V7,
    ]
  }

  config: #Dubo & {
    target: "config"
    args: {
      BUILD_TITLE: "Rudder Config"
      BUILD_DESCRIPTION: "A dubo image for Rudder based on \(args.DEBOOTSTRAP_SUITE) (\(args.DEBOOTSTRAP_DATE))"
      BASE_BASE: string | * "docker.io/dubodubonduponey/base"
      BUILDER_BASE: "\(BASE_BASE):builder-node-\(args.DEBOOTSTRAP_SUITE)-\(args.DEBOOTSTRAP_DATE)"
    }
    platforms: [
      AMD64,
      ARM64,
      V7,
    ]
  }

}
