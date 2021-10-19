package cake

import (
	"duponey.cloud/scullery"
	"duponey.cloud/buildkit/types"
	"strings"
)

cakes: {
  server: scullery.#Cake & {
		recipe: {
			input: {
				from: {
					registry: * "ghcr.io/dubo-dubon-duponey" | string
				}
			}

			process: {
				// XXX a dependency (badger) overflows int on 32
				target: "server"
				platforms: types.#Platforms | * [
					types.#Platforms.#AMD64,
					types.#Platforms.#ARM64,
				]
			}

			output: {
				images: {
					names: [...string] | * ["elastic"],
					tags: [...string] | * ["latest"]
				}
			}

			metadata: {
				title: string | * "Dubo Elastic",
				description: string | * "A dubo image for Elastic",
			}
		}
  }
  config: scullery.#Cake & {
		recipe: {
			input: {
				from: {
					registry: * "ghcr.io/dubo-dubon-duponey" | string
				}
			}

			process: {
				target: "config"
				platforms: types.#Platforms | * [
					types.#Platforms.#AMD64,
					types.#Platforms.#ARM64,
					types.#Platforms.#I386,
					types.#Platforms.#V7,
					types.#Platforms.#S390X,
					types.#Platforms.#PPC64LE,
				]
			}

			output: {
				images: {
					names: [...string] | * ["rudder"],
					tags: [...string] | * ["latest"]
				}
			}

			metadata: {
				title: string | * "Dubo Rudder",
				description: string | * "A dubo image for Rudder",
			}
		}
  }
}

injectors: {
	suite: * "bullseye" | =~ "^(?:jessie|stretch|buster|bullseye|sid)$" @tag(suite, type=string)
	date: * "2021-10-15" | =~ "^[0-9]{4}-[0-9]{2}-[0-9]{2}$" @tag(date, type=string)
	platforms: string @tag(platforms, type=string)
	registry: * "registry.local" | string @tag(registry, type=string)
}

overrides: {
	input: from: registry: injectors.registry

	if injectors.platforms != _|_ {
		process: platforms: strings.Split(injectors.platforms, ",")
	}


	output: images: tags: [injectors.suite + "-" + injectors.date, injectors.suite + "-latest", "latest"]
	metadata: ref_name: injectors.suite + "-" + injectors.date
}

// Allow hooking-in a UserDefined environment as icing
UserDefined: scullery.#Icing

cakes: server: recipe: overrides
cakes: config: recipe: overrides
cakes: server: icing: UserDefined
cakes: config: icing: UserDefined
