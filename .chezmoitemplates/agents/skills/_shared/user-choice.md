Present the options and have the user choose. On agents with a selection UI tool, meaning a tool whose purpose is to present labelled options and receive the user's pick (`AskUserQuestion` and similar), call that tool. On agents without one, present the same options as a numbered plain-text list and let the user answer by number or free text. Either way, do not move on until you have an answer.

Never name the tool again in the steps below. Where a step says "selection prompt" or "ask the user to choose", it means whatever this paragraph resolved to.
