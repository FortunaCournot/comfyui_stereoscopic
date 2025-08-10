# https://pypi.org/project/googletrans/#description

import sys
import asyncio
from googletrans import Translator

async def translate_text(dest, text):
    async with Translator() as translator:
        try:
            result = await translator.translate(text, src='en', dest=dest)
            sys.stdout.reconfigure(encoding='utf-8')
            print(result.text)
        except:
            print(text)

if len(sys.argv) == 2 + 1:
    asyncio.run(translate_text(sys.argv[1], sys.argv[2]))
else:
    print("Invalid arguments were given ("+ str(len(sys.argv)-1) +"). Usage: python " + sys.argv[0] + " dest text")
