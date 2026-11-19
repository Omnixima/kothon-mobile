// The keyboard's emoji, bundled (keyboards can't open Apple's emoji panel).
// Common Unicode emoji by category, most used first in each. Drawn with the
// system emoji font.

import Foundation

struct EmojiCategory: Identifiable {
    let id: String
    let symbol: String  // SF Symbol for the tab
    let name: String    // VoiceOver
    let emoji: [String]
}

enum EmojiData {
    static func split(_ s: String) -> [String] { s.split(separator: " ").map(String.init) }

    static let categories: [EmojiCategory] = [
        EmojiCategory(id: "faces", symbol: "face.smiling", name: "মুখ", emoji: split("""
        😀 😃 😄 😁 😆 😅 😂 🤣 🥲 ☺️ 😊 😇 🙂 🙃 😉 😌 😍 🥰 😘 😗 😙 😚 😋 😛 😝 😜 🤪 🤨 🧐 🤓 😎 🥸 🤩 🥳 😏 😒 \
        😞 😔 😟 😕 🙁 ☹️ 😣 😖 😫 😩 🥺 😢 😭 😮‍💨 😤 😠 😡 🤬 🤯 😳 🥵 🥶 😱 😨 😰 😥 😓 🫣 🤗 🫡 🤔 🫢 🤭 🤫 \
        🤥 😶 😐 😑 😬 🫠 🙄 😯 😦 😧 😮 😲 🥱 😴 🤤 😪 😵 🤐 🥴 🤢 🤮 🤧 😷 🤒 🤕 🤑 🤠 😈 👿 👹 👺 🤡 💩 👻 \
        💀 ☠️ 👽 👾 🤖 🎃 😺 😸 😹 😻 😼 😽 🙀 😿 😾
        """)),
        EmojiCategory(id: "people", symbol: "hand.wave", name: "হাত ও মানুষ", emoji: split("""
        👋 🤚 🖐️ ✋ 🖖 👌 🤌 🤏 ✌️ 🤞 🫰 🤟 🤘 🤙 👈 👉 👆 🖕 👇 ☝️ 🫵 👍 👎 ✊ 👊 🤛 🤜 👏 🙌 🫶 👐 🤲 🤝 🙏 \
        ✍️ 💅 🤳 💪 🦾 🦵 🦶 👂 👃 🧠 👀 👁️ 👅 👄 🫦 👶 🧒 👦 👧 🧑 👱 👨 🧔 👩 🧓 👴 👵 🙍 🙎 🙅 🙆 💁 🙋 🧏 \
        🙇 🤦 🤷 👮 🕵️ 💂 👷 🤴 👸 👳 👲 🧕 🤵 👰 🤰 🤱 👼 🎅 🦸 🦹 🧙 🧚 🧛 🧜 🧝 🧞 🧟 💆 💇 🚶 🧍 🧎 🏃 💃 \
        🕺 👯 🧖 🧗 🏇 🏂 🏌️ 🏄 🚣 🏊 ⛹️ 🏋️ 🚴 🚵 🤸 🤼 🤽 🤾 🤹 🧘 🛀 🛌 👭 👫 👬 💏 💑 👪 🗣️ 👤 👥 🫂
        """)),
        EmojiCategory(id: "hearts", symbol: "heart", name: "ভালোবাসা", emoji: split("""
        ❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 🩷 🩵 🩶 💔 ❤️‍🔥 ❤️‍🩹 ❣️ 💕 💞 💓 💗 💖 💘 💝 💟 💋 💌 💐 🌹 🥀 🌷 🌸 💮 \
        ✨ ⭐ 🌟 💫 🔥 💥 💯 💢 💦 💨 🕊️ 🎉 🎊 🎁 🎈 🎀
        """)),
        EmojiCategory(id: "nature", symbol: "leaf", name: "প্রাণী ও প্রকৃতি", emoji: split("""
        🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐻‍❄️ 🐨 🐯 🦁 🐮 🐷 🐸 🐵 🙈 🙉 🙊 🐒 🐔 🐧 🐦 🐤 🐣 🐥 🦆 🦅 🦉 🦇 🐺 🐗 🐴 🦄 \
        🐝 🪱 🐛 🦋 🐌 🐞 🐜 🪰 🦟 🦗 🕷️ 🦂 🐢 🐍 🦎 🦖 🦕 🐙 🦑 🦐 🦞 🦀 🐡 🐠 🐟 🐬 🐳 🐋 🦈 🐊 🐅 🐆 🦓 🦍 \
        🐘 🦛 🦏 🐪 🐫 🦒 🦘 🐃 🐂 🐄 🐎 🐖 🐏 🐑 🐐 🦌 🐕 🐈 🐓 🦃 🦚 🦜 🦢 🦩 🐇 🐿️ 🦔 🌵 🎄 🌲 🌳 🌴 🌱 🌿 \
        ☘️ 🍀 🎍 🎋 🍃 🍂 🍁 🍄 🐚 🌾 💐 🌺 🌻 🌼 🌞 🌝 🌛 🌜 🌚 🌕 🌙 🌎 🌍 🌏 🪐 💫 ⭐ ⚡ ☄️ ☀️ 🌤️ ⛅ 🌥️ ☁️ \
        🌦️ 🌧️ ⛈️ 🌩️ 🌨️ ❄️ ☃️ ⛄ 🌬️ 🌪️ 🌫️ 🌈 ☔ 💧 🌊
        """)),
        EmojiCategory(id: "food", symbol: "fork.knife", name: "খাবার", emoji: split("""
        🍏 🍎 🍐 🍊 🍋 🍌 🍉 🍇 🍓 🫐 🍈 🍒 🍑 🥭 🍍 🥥 🥝 🍅 🍆 🥑 🥦 🥬 🥒 🌶️ 🫑 🌽 🥕 🧄 🧅 🥔 🍠 🥐 🍞 🥖 \
        🧀 🥚 🍳 🧈 🥞 🧇 🥓 🥩 🍗 🍖 🌭 🍔 🍟 🍕 🥪 🌮 🌯 🥗 🥘 🍝 🍜 🍲 🍛 🍣 🍱 🥟 🍤 🍙 🍚 🍘 🍥 🥠 🍢 🍡 \
        🍧 🍨 🍦 🥧 🧁 🍰 🎂 🍮 🍭 🍬 🍫 🍿 🍩 🍪 🌰 🥜 🍯 🥛 🍼 ☕ 🫖 🍵 🧃 🥤 🧋 🍶 🍺 🍻 🥂 🍷 🥃 🍸 🍹 🧉 🧊 🥢 🍽️ 🍴 🥄
        """)),
        EmojiCategory(id: "activity", symbol: "soccerball", name: "খেলা ও কাজ", emoji: split("""
        ⚽ 🏀 🏈 ⚾ 🥎 🎾 🏐 🏉 🥏 🎱 🏓 🏸 🏒 🏑 🥍 🏏 🪃 🥅 ⛳ 🪁 🏹 🎣 🤿 🥊 🥋 🎽 🛹 🛼 🛷 ⛸️ 🥌 🎿 🏆 🥇 \
        🥈 🥉 🏅 🎖️ 🎗️ 🎫 🎟️ 🎪 🎭 🎨 🎬 🎤 🎧 🎼 🎹 🥁 🎷 🎺 🎸 🪕 🎻 🎲 ♟️ 🎯 🎳 🎮 🎰 🧩
        """)),
        EmojiCategory(id: "travel", symbol: "car", name: "যাতায়াত ও জায়গা", emoji: split("""
        🚗 🚕 🚙 🚌 🚎 🏎️ 🚓 🚑 🚒 🚐 🛻 🚚 🚛 🚜 🛵 🏍️ 🛺 🚲 🛴 🚨 🚔 🚍 🚘 🚖 🚡 🚠 🚟 🚃 🚋 🚞 🚝 🚄 🚅 🚈 \
        🚂 🚆 🚇 🚊 🚉 ✈️ 🛫 🛬 💺 🚀 🛸 🚁 🛶 ⛵ 🚤 🛥️ 🛳️ ⛴️ 🚢 ⚓ ⛽ 🚧 🚦 🚥 🗺️ 🗿 🗽 🗼 🏰 🏯 🏟️ 🎡 🎢 🎠 \
        ⛲ ⛱️ 🏖️ 🏝️ 🏜️ 🌋 ⛰️ 🏔️ 🗻 🏕️ ⛺ 🏠 🏡 🏘️ 🏚️ 🏗️ 🏭 🏢 🏬 🏣 🏤 🏥 🏦 🏨 🏪 🏫 🏩 💒 🏛️ ⛪ 🕌 🛕 🕍 🕋 ⛩️ 🌅 🌄 🌠 🎇 🎆 🌇 🌆 🏙️ 🌃 🌌 🌉 🌁
        """)),
        EmojiCategory(id: "objects", symbol: "lightbulb", name: "জিনিস", emoji: split("""
        ⌚ 📱 💻 ⌨️ 🖥️ 🖨️ 🖱️ 💽 💾 💿 📀 📷 📸 📹 🎥 📞 ☎️ 📺 📻 🎙️ ⏰ ⏳ ⌛ 📡 🔋 🔌 💡 🔦 🕯️ 💸 💵 💴 💶 💷 \
        💰 💳 💎 ⚖️ 🔧 🔨 ⚒️ 🛠️ ⛏️ 🔩 ⚙️ 🧱 ⛓️ 🧲 🔫 💣 🔪 🗡️ ⚔️ 🛡️ 🚬 ⚰️ 🔮 📿 💈 🔭 🔬 🩹 🩺 💊 💉 🧬 🦠 🌡️ \
        🧹 🧺 🧻 🚽 🚿 🛁 🧼 🪥 🧽 🛎️ 🔑 🗝️ 🚪 🪑 🛋️ 🛏️ 🧸 🖼️ 🛍️ 🛒 🎁 🎈 ✉️ 📩 📨 📧 💌 📮 📦 🏷️ 📜 📃 📄 📑 \
        📊 📈 📉 🗒️ 🗓️ 📆 📅 📇 🗃️ 🗳️ 🗄️ 📋 📁 📂 🗂️ 🗞️ 📰 📓 📔 📒 📕 📗 📘 📙 📚 📖 🔖 🔗 📎 🖇️ 📐 📏 📌 📍 \
        ✂️ 🖊️ 🖋️ ✒️ 🖌️ 🖍️ 📝 ✏️ 🔍 🔎 🔏 🔐 🔒 🔓
        """)),
        EmojiCategory(id: "symbols", symbol: "number", name: "চিহ্ন", emoji: split("""
        ✅ ☑️ ✔️ ❌ ❎ ➕ ➖ ➗ ✖️ ♾️ ‼️ ⁉️ ❓ ❔ ❕ ❗ 〰️ ➰ ➿ ⭕ 🛑 ⛔ 📛 🚫 💯 🔞 📵 🚭 ♻️ ⚠️ 🚸 🔱 ⚜️ 🔰 \
        🆗 🆕 🆓 🆒 🆙 🆘 🆚 ℹ️ 🔤 🔡 🔠 🔢 #️⃣ *️⃣ 0️⃣ 1️⃣ 2️⃣ 3️⃣ 4️⃣ 5️⃣ 6️⃣ 7️⃣ 8️⃣ 9️⃣ 🔟 ▶️ ⏸️ ⏹️ ⏺️ ⏭️ ⏮️ ⏩ ⏪ \
        🔀 🔁 🔂 ◀️ 🔼 🔽 ⬆️ ⬇️ ➡️ ⬅️ ↗️ ↘️ ↙️ ↖️ ↕️ ↔️ ↪️ ↩️ ⤴️ ⤵️ 🔃 🔄 🎵 🎶 ™️ ©️ ®️ 💲 💱 🔔 🔕 📣 📢 💬 💭 🗯️ \
        ♠️ ♣️ ♥️ ♦️ 🃏 🎴 🀄 🕐 🕑 🕒 🕓 🕔 🕕 🕖 🕗 🕘 🕙 🕚 🕛 🔴 🟠 🟡 🟢 🔵 🟣 🟤 ⚫ ⚪ 🟥 🟧 🟨 🟩 🟦 🟪 🟫 ⬛ ⬜ \
        ☪️ 🕉️ ☸️ ✡️ ☯️ ✝️ ☦️ 🛐 ☮️ 🕎 🔯 ♈ ♉ ♊ ♋ ♌ ♍ ♎ ♏ ♐ ♑ ♒ ♓
        """)),
        EmojiCategory(id: "flags", symbol: "flag", name: "পতাকা", emoji: split("""
        🇧🇩 🇮🇳 🇵🇰 🇳🇵 🇱🇰 🇧🇹 🇲🇻 🇦🇫 🇲🇲 🇨🇳 🇯🇵 🇰🇷 🇸🇬 🇲🇾 🇹🇭 🇮🇩 🇵🇭 🇻🇳 🇸🇦 🇦🇪 🇶🇦 🇰🇼 🇴🇲 🇧🇭 🇹🇷 🇮🇷 🇮🇶 🇪🇬 \
        🇬🇧 🇺🇸 🇨🇦 🇦🇺 🇳🇿 🇩🇪 🇫🇷 🇮🇹 🇪🇸 🇵🇹 🇳🇱 🇧🇪 🇸🇪 🇳🇴 🇩🇰 🇫🇮 🇮🇪 🇨🇭 🇦🇹 🇵🇱 🇷🇺 🇺🇦 🇧🇷 🇦🇷 🇲🇽 🇿🇦 🇳🇬 🇰🇪 \
        🏳️ 🏴 🏁 🚩 🏳️‍🌈 🇺🇳
        """)),
    ]
}
