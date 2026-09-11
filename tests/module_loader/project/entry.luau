local first = require("./nested/first")
local firstAgain = require("./nested/./first")
local feature = require("./feature")
local aliased = require("@shared/value")

return {
    answer = first.answer + feature + aliased,
    sameModule = first == firstAgain,
}
