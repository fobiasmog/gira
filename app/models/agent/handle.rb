# The generated address of an agent (spec agents, "Agent accounts"; add-agents
# design.md, decision 2): <adjective>-<animal>-<nnnn> on the agent domain,
# about 10^8 combinations. Nobody chooses it, and it says nothing about the
# agent's name or its creator.
module Agent::Handle
  ADJECTIVES = %w[
    amber ancient arctic autumn azure bold brave bright brisk bronze calm candid cedar cheerful clever cobalt copper coral
    cosmic crimson crisp curious daring dawn deft distant dusty eager early earnest ebony emerald fabled fair fearless
    fleet fluent frosty gentle gilded glad golden graceful grand hardy hazel hidden honest humble indigo ivory jade
    jolly keen kind lively loyal lucky lunar maple mellow merry mighty misty modest nimble noble olive opal patient
    pearl placid plucky polar proud quick quiet rapid rosy royal ruby rustic sable sage scarlet serene silent silver
    sleek snowy solar steady stellar stormy sturdy sunny swift tidal tranquil trusty velvet vivid wise witty
  ].freeze

  ANIMALS = %w[
    alpaca antelope badger bat bear beaver bison boar buffalo camel caribou cat cheetah cobra condor cougar coyote crab
    crane crow deer dingo dolphin dove dragonfly eagle falcon ferret finch fish fox frog gazelle gecko gibbon goat goose
    gull hare hawk hedgehog heron horse ibex ibis jackal jaguar kestrel kiwi koala lark lemur leopard lion lizard llama
    lynx magpie marten mole moose moth newt ocelot orca osprey otter owl panda panther parrot pelican penguin pike
    puffin puma quail rabbit raven robin salmon seal shark sparrow squid stork swan tapir tern tiger toad trout turtle
    viper walrus weasel whale wolf wombat wren yak zebra
  ].freeze

  NUMBERS = 10_000

  def self.generate
    "#{ADJECTIVES.sample(random: SecureRandom)}-#{ANIMALS.sample(random: SecureRandom)}-#{format('%04d', SecureRandom.random_number(NUMBERS))}@#{Agent.email_domain}"
  end
end
