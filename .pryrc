# Do not have to prepend all methods with FactoryBot
require 'factory_bot'
FactoryBot.find_definitions
include FactoryBot::Syntax::Methods
