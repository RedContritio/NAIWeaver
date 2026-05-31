/// Tag → slot lookup table, ported from bri.'s `app/outfit_slots.py`
/// (`_SEED_TAG_TO_SLOT`) merged with the Danbooru-scraped extension table
/// (`app/outfit_slots_data.py`). The hand-curated seed entries win on conflict
/// (mirrors Python's `merged.setdefault`).
///
/// Keys are lowercase. The classifier (outfit_classifier.dart) does an exact
/// lookup here first, then falls back to whole-word substring matching against
/// these keys grouped by slot.
library;

/// Hand-curated baseline. Wins over [_scrapedTagToSlot] on key conflict.
const Map<String, String> _seedTagToSlot = <String, String>{
  // top
  'blouse': 'top', 'shirt': 'top', 't-shirt': 'top', 'tank top': 'top',
  'crop top': 'top', 'camisole': 'top', 'sweater': 'top', 'hoodie': 'top',
  'turtleneck': 'top', 'tube top': 'top', 'halter top': 'top', 'bandeau': 'top',
  'polo shirt': 'top', 'dress shirt': 'top', 'button-up shirt': 'top',
  'pullover': 'top', 'vest': 'top', 'jersey': 'top', 'sweatshirt': 'top',
  'long sleeve shirt': 'top', 'short sleeve shirt': 'top',

  // dress (own slot — replaces top+bottom)
  'dress': 'dress', 'sundress': 'dress', 'evening dress': 'dress',
  'cocktail dress': 'dress', 'gown': 'dress', 'kimono': 'dress',
  'yukata': 'dress', 'nightgown': 'dress', 'one-piece dress': 'dress',
  'maid dress': 'dress',

  // bottom
  'skirt': 'bottom', 'miniskirt': 'bottom', 'pleated skirt': 'bottom',
  'pencil skirt': 'bottom', 'maxi skirt': 'bottom', 'pants': 'bottom',
  'jeans': 'bottom', 'shorts': 'bottom', 'hot pants': 'bottom',
  'sweatpants': 'bottom', 'leggings': 'bottom', 'cargo pants': 'bottom',
  'capri pants': 'bottom', 'track pants': 'bottom', 'denim shorts': 'bottom',
  'culottes': 'bottom', 'bike shorts': 'bottom', 'board shorts': 'bottom',
  'slacks': 'bottom', 'dress slacks': 'bottom', 'slim-fit slacks': 'bottom',
  'trousers': 'bottom', 'dress trousers': 'bottom', 'dress pants': 'bottom',
  'chinos': 'bottom', 'khakis': 'bottom',

  // bra / underwear top
  'bra': 'bra', 'sports bra': 'bra', 'strapless bra': 'bra', 'bralette': 'bra',
  'balconette bra': 'bra', 'balcony bra': 'bra', 'demi bra': 'bra',
  'demi-cup bra': 'bra', 'push-up bra': 'bra', 'plunge bra': 'bra',
  't-shirt bra': 'bra', 'underwire bra': 'bra', 'lace bra': 'bra',

  // panties
  'panties': 'panties', 'thong': 'panties', 'boyshorts': 'panties',
  'g-string': 'panties', 'bikini bottom': 'panties',
  'hipster panties': 'panties', 'hipsters': 'panties',
  'bikini panties': 'panties', 'brief panties': 'panties',
  'briefs': 'panties', 'boyleg panties': 'panties', 'boy shorts': 'panties',
  'lace panties': 'panties', 'cheeky panties': 'panties',
  'loincloth': 'panties', 'loin cloth': 'panties',
  'perizoma': 'panties',
  'subligaculum': 'panties',
  'fundoshi': 'panties',
  'malo': 'panties',
  'bloomers': 'panties', 'knee-length bloomers': 'panties',
  'silk bloomers': 'panties', 'cotton bloomers': 'panties',
  'split bloomers': 'panties',
  'knickers': 'panties', 'drawers': 'panties',
  'pantalettes': 'panties', 'pantalets': 'panties',
  'tap pants': 'panties',
  // men's underwear (modern + historical) — the pelvic base layer for male
  // characters. Routes to the `panties` slot so the same pull/aside/removed
  // state machine drives them (the slot is "pelvic base layer", not gendered).
  'boxers': 'panties', 'boxer briefs': 'panties', 'boxer shorts': 'panties',
  "men's briefs": 'panties', 'mens briefs': 'panties',
  'trunks': 'panties', 'underwear trunks': 'panties',
  'braies': 'panties', 'braccae': 'panties', 'breechcloth': 'panties',
  // men's torso base layer (worn next to the skin under outer tops). Routes to
  // the `bra` slot — the chest base-layer slot — same as `sarashi`.
  'undershirt': 'bra', 'linen undershirt': 'bra',
  'brassiere': 'bra',
  'corset cover': 'bra',
  'bandeau bra': 'bra',
  'petticoat': 'panties', 'lace petticoat': 'panties',

  // outerwear
  'jacket': 'outerwear', 'coat': 'outerwear', 'blazer': 'outerwear',
  'cardigan': 'outerwear', 'windbreaker': 'outerwear', 'parka': 'outerwear',
  'bomber jacket': 'outerwear', 'trench coat': 'outerwear',
  'leather jacket': 'outerwear', 'raincoat': 'outerwear', 'fur coat': 'outerwear',
  'robe': 'outerwear', 'kimono jacket': 'outerwear',
  'cloak': 'outerwear', 'wool cloak': 'outerwear', 'fur cloak': 'outerwear',
  'hooded cloak': 'outerwear', 'travelling cloak': 'outerwear',
  'cape': 'outerwear', 'short cape': 'outerwear', 'long cape': 'outerwear',
  'mantle': 'outerwear', 'shawl': 'outerwear', 'wrap': 'outerwear',
  'surcoat': 'outerwear', 'tabard': 'outerwear', 'heraldic surcoat': 'outerwear',
  'haori': 'outerwear', 'happi': 'outerwear', 'dotera': 'outerwear',
  'poncho': 'outerwear', 'serape': 'outerwear',

  // legwear
  'thighhighs': 'legwear', 'stockings': 'legwear', 'pantyhose': 'legwear',
  'kneehighs': 'legwear', 'socks': 'legwear', 'tights': 'legwear',
  'fishnets': 'legwear', 'leg warmers': 'legwear', 'over-knee socks': 'legwear',

  // footwear
  'shoes': 'footwear', 'boots': 'footwear', 'sneakers': 'footwear',
  'heels': 'footwear', 'high heels': 'footwear', 'sandals': 'footwear',
  'flip-flops': 'footwear', 'loafers': 'footwear', 'slippers': 'footwear',
  'ballet flats': 'footwear', 'mary janes': 'footwear', 'pumps': 'footwear',
  'converse': 'footwear', 'uwabaki': 'footwear', 'geta': 'footwear',

  // headwear
  'hat': 'headwear', 'cap': 'headwear', 'beanie': 'headwear',
  'beret': 'headwear', 'headband': 'headwear', 'baseball cap': 'headwear',
  'sun hat': 'headwear', 'straw hat': 'headwear', 'hood': 'headwear',
  'helmet': 'headwear', 'helm': 'headwear', 'great helm': 'headwear',
  'combat helmet': 'headwear', 'winged helmet': 'headwear',
  'spiked helmet': 'headwear', 'pith helmet': 'headwear',
  'kabuto': 'headwear', 'kabuto (helmet)': 'headwear',
  'armet': 'headwear', 'bascinet': 'headwear', 'sallet': 'headwear',
  'morion': 'headwear', 'kettle helm': 'headwear', 'barbute': 'headwear',
  'nasal helmet': 'headwear', 'greek helmet': 'headwear',
  'roman helmet': 'headwear', 'spartan helmet': 'headwear',
  'visor': 'headwear', 'visor (armor)': 'headwear',

  // accessory
  'gloves': 'accessory', 'scarf': 'accessory', 'tie': 'accessory',
  'bow tie': 'accessory', 'belt': 'accessory', 'necklace': 'accessory',
  'earrings': 'accessory', 'earring': 'accessory', 'glasses': 'accessory',
  'bracelet': 'accessory', 'watch': 'accessory', 'ring': 'accessory',
  'hair ribbon': 'accessory', 'hair bow': 'accessory', 'choker': 'accessory',
  'collar': 'accessory', 'ear cozies': 'accessory', 'ear cozy': 'accessory',
  'ear muffs': 'accessory', 'earmuffs': 'accessory', 'ear warmers': 'accessory',
  'ear cuff': 'accessory', 'ear cuffs': 'accessory',
  'ribbon tie': 'accessory', 'velvet ribbon': 'accessory',
  'apron': 'accessory', 'lace apron': 'accessory',
  'bracers': 'accessory', 'vambrace': 'accessory', 'vambraces': 'accessory',
  'rerebrace': 'accessory', 'couter': 'accessory', 'rondel': 'accessory',
  'gauntlet': 'accessory', 'gauntlets': 'accessory',
  'pauldron': 'accessory', 'pauldrons': 'accessory', 'spaulders': 'accessory',
  'sode': 'accessory', 'kote': 'accessory', 'kurokote': 'accessory',
  'gorget': 'accessory', 'aventail': 'accessory', 'bevor': 'accessory',
  'shikoro': 'accessory', 'nodowa': 'accessory',
  'greaves': 'accessory', 'sabaton': 'accessory', 'sabatons': 'accessory',
  'cuisses': 'accessory', 'poleyn': 'accessory', 'poleyns': 'accessory',
  'armored boots': 'footwear',
  'faulds': 'accessory', 'kusazuri': 'accessory', 'tassets': 'accessory',
  'shin guards': 'accessory', 'knee guards': 'accessory',
  'leg armor': 'accessory', 'plackart': 'accessory',
  'shield': 'accessory', 'buckler': 'accessory', 'tower shield': 'accessory',
  'kite shield': 'accessory', 'round shield': 'accessory',
  'riot shield': 'accessory', 'ballistic shield': 'accessory',

  // armor — hard torso pieces
  'armor': 'armor',
  'breastplate': 'armor', 'cuirass': 'armor', 'muscle cuirass': 'armor',
  'plate armor': 'armor', 'plate mail': 'armor',
  'full armor': 'armor', 'full plate armor': 'armor',
  'chainmail': 'armor', 'chain mail': 'armor', 'ringmail': 'armor',
  'ring mail': 'armor',
  'hauberk': 'armor', 'mail shirt': 'armor', 'mail hauberk': 'armor',
  'scale armor': 'armor', 'scale mail': 'armor', 'lamellar armor': 'armor',
  'brigandine': 'armor',
  'leather armor': 'armor',
  'japanese armor': 'armor', 'samurai armor': 'armor',
  'muneate': 'armor', 'dou': 'armor', 'do-maru': 'armor', 'o-yoroi': 'armor',
  'bougu': 'armor', 'kendo armor': 'armor',
  'body armor': 'armor', 'bulletproof vest': 'armor', 'tactical vest': 'armor',
  'power armor': 'armor', 'power suit': 'armor', 'exoskeleton': 'armor',
  'ornate armor': 'armor', 'broken armor': 'armor',
  'barding': 'armor',
  'armored dress': 'armor', 'armored skirt': 'armor',

  // padded armor under-layers → top
  'gambeson': 'top', 'quilted gambeson': 'top', 'padded gambeson': 'top',
  'doublet': 'top', 'arming doublet': 'top', 'arming jacket': 'top',
  'padded armor': 'top', 'padded jacket': 'top', 'padded tunic': 'top',
  'jerkin': 'top', 'leather jerkin': 'top',
  'tunic': 'top', 'linen tunic': 'top',

  // historical / non-Western body-covering garments
  'chiton': 'dress', 'doric chiton': 'dress', 'ionic chiton': 'dress',
  'greek chiton': 'dress', 'white chiton': 'dress',
  'peplos': 'dress', 'stola': 'dress',
  'himation': 'outerwear',
  'chlamys': 'outerwear',
  'toga': 'dress',
  'kosode': 'top',
  'juban': 'top', 'nagajuban': 'top',
  'hanfu': 'dress', 'ruqun': 'dress',
  'saree': 'dress', 'sari': 'dress', 'sarong': 'dress',
  'dhoti': 'bottom', 'lungi': 'bottom',
  'kilt': 'bottom', 'linen kilt': 'bottom', 'egyptian kilt': 'bottom',
  'shendyt': 'bottom',
};

/// Danbooru-scraped extension table (`app/outfit_slots_data.py`). Used only
/// for keys NOT already in [_seedTagToSlot].
const Map<String, String> _scrapedTagToSlot = <String, String>{
  // -- accessory --
  'aiguillette': 'accessory', 'animal costume': 'accessory',
  'animal print': 'accessory', 'ankle strap': 'accessory', 'anklet': 'accessory',
  'apple print': 'accessory', 'apron': 'accessory', 'arm belt': 'accessory',
  'arm guards': 'accessory', 'arm warmers': 'accessory', 'armband': 'accessory',
  'armlet': 'accessory', 'armor': 'accessory', 'ascot': 'accessory',
  'badge': 'accessory', 'band uniform': 'accessory', 'bangle': 'accessory',
  'bat print': 'accessory', 'bear costume': 'accessory', 'bear print': 'accessory',
  'belly chain': 'accessory', 'belt': 'accessory', 'bikini armor': 'accessory',
  'bone print': 'accessory', 'boutonniere': 'accessory', 'bowtie': 'accessory',
  'boxing gloves': 'accessory', 'bracelet': 'accessory', 'bracer': 'accessory',
  'bridal gauntlets': 'accessory', 'brooch': 'accessory', 'buckle': 'accessory',
  'business suit': 'accessory', 'butterfly print': 'accessory',
  'button badge': 'accessory', 'buttoned cuffs': 'accessory',
  'buttons': 'accessory', 'camellia print': 'accessory',
  'camouflage': 'accessory', 'casual': 'accessory', 'cat costume': 'accessory',
  'cheerleader': 'accessory', 'cherry blossom print': 'accessory',
  'cherry print': 'accessory', 'chinese knot': 'accessory', 'choker': 'accessory',
  'chrysanthemum print': 'accessory', 'circlet': 'accessory',
  'claw ring': 'accessory', 'clothing cutout': 'accessory',
  'clover print': 'accessory', 'collar': 'accessory', 'corsage': 'accessory',
  'cosplay': 'accessory', 'costume': 'accessory', 'cow costume': 'accessory',
  'cow print': 'accessory', 'cowboy western': 'accessory',
  'crescent print': 'accessory', 'crinoline': 'accessory',
  'criss-cross back-straps': 'accessory', 'criss-cross straps': 'accessory',
  'cross tie': 'accessory', 'cuff links': 'accessory',
  'detached sleeves': 'accessory', 'dog costume': 'accessory',
  'double vertical stripe': 'accessory', 'double-breasted': 'accessory',
  'dress flower': 'accessory', 'ear chain': 'accessory', 'ear covers': 'accessory',
  'earclip': 'accessory', 'earphones': 'accessory', 'earpiece': 'accessory',
  'earrings': 'accessory', 'elbow gloves': 'accessory', 'elbow sleeve': 'accessory',
  'epaulettes': 'accessory', 'fanny pack': 'accessory', 'fashion': 'accessory',
  'feather boa': 'accessory', 'fingerless gloves': 'accessory',
  'fingernails': 'accessory', 'floral print': 'accessory',
  'flower trim': 'accessory', 'food print': 'accessory',
  'formal clothes': 'accessory', 'frilled thigh strap': 'accessory',
  'frills': 'accessory', 'fur trim': 'accessory', 'gakuran': 'accessory',
  'garter belt': 'accessory', 'garter straps': 'accessory', 'gathers': 'accessory',
  'ghost costume': 'accessory', 'glasses': 'accessory', 'gloves': 'accessory',
  'gold trim': 'accessory', 'guimpe': 'accessory', 'gym uniform': 'accessory',
  'hair beads': 'accessory', 'hair bobbles': 'accessory',
  'hair ornament': 'accessory', 'hair scrunchie': 'accessory',
  'hair stick': 'accessory', 'hairclip': 'accessory', 'hairpin': 'accessory',
  'harem outfit': 'accessory', 'harness': 'accessory', 'hazmat suit': 'accessory',
  'head chain': 'accessory', 'headphones': 'accessory', 'headset': 'accessory',
  'hoop earrings': 'accessory', 'houndstooth': 'accessory',
  'jersey maid': 'accessory', 'kanzashi': 'accessory', 'kigurumi': 'accessory',
  'lace trim': 'accessory', 'lapel pin': 'accessory', 'lapels': 'accessory',
  'large buttons': 'accessory', 'laurel crown': 'accessory',
  'leaf print': 'accessory', 'leg belt': 'accessory', 'legwear garter': 'accessory',
  'lemon print': 'accessory', 'leopard print': 'accessory',
  'lolita fashion': 'accessory', 'maid': 'accessory', 'maple leaf print': 'accessory',
  'mask': 'accessory', 'mecha pilot suit': 'accessory',
  'meiji schoolgirl uniform': 'accessory', 'miko': 'accessory',
  'military uniform': 'accessory', 'mittens': 'accessory', 'monocle': 'accessory',
  'moon print': 'accessory', 'morning glory print': 'accessory',
  'multicolored stripes': 'accessory', 'musical note print': 'accessory',
  'neck ribbon': 'accessory', 'neck ruff': 'accessory', 'neckerchief': 'accessory',
  'necklace': 'accessory', 'necktie': 'accessory', 'nontraditional miko': 'accessory',
  'nun': 'accessory', 'orange print': 'accessory', 'overalls': 'accessory',
  'panda costume': 'accessory', 'pant suit': 'accessory', 'paw print': 'accessory',
  'penguin costume': 'accessory', 'pentacle': 'accessory', 'peony print': 'accessory',
  'petal print': 'accessory', 'piano print': 'accessory', 'piercing': 'accessory',
  'pinstripe pattern': 'accessory', 'plague doctor mask': 'accessory',
  'plaid': 'accessory', 'plum blossom print': 'accessory', 'pocket watch': 'accessory',
  'polka dot': 'accessory', 'priest': 'accessory', 'rabbit costume': 'accessory',
  'reindeer costume': 'accessory', 'ribbon trim': 'accessory', 'ring': 'accessory',
  'rose print': 'accessory', 'sailor': 'accessory', 'sam browne belt': 'accessory',
  'santa costume': 'accessory', 'scarf': 'accessory', 'school uniform': 'accessory',
  'see-through clothes': 'accessory', 'serafuku': 'accessory', 'shawl': 'accessory',
  'sheep costume': 'accessory', 'shin guards': 'accessory', 'shin strap': 'accessory',
  'shosei': 'accessory', 'shoulder belt': 'accessory', 'side cape': 'accessory',
  'silver trim': 'accessory', 'skirt suit': 'accessory', 'snake print': 'accessory',
  'space print': 'accessory', 'sparkle print': 'accessory',
  'spider lily print': 'accessory', 'spiked bracelet': 'accessory',
  'spiked gloves': 'accessory', 'star print': 'accessory',
  'starry sky print': 'accessory', 'strawberry print': 'accessory',
  'stud earrings': 'accessory', 'suit': 'accessory', 'sunflower print': 'accessory',
  'surgical mask': 'accessory', 'suspenders': 'accessory', 'sweater guard': 'accessory',
  'sweatpants': 'accessory', 'tassel': 'accessory', 'taut shirt': 'accessory',
  'thigh strap': 'accessory', 'thighlet': 'accessory', 'tie clip': 'accessory',
  'tiger costume': 'accessory', 'tiger print': 'accessory', 'torn clothes': 'accessory',
  'track suit': 'accessory', 'traditional nun': 'accessory', 'triangle print': 'accessory',
  'tuxedo': 'accessory', 'usekh collar': 'accessory', 'waist sash': 'accessory',
  'waitress': 'accessory', 'wallet chain': 'accessory', 'watch': 'accessory',
  'watermelon print': 'accessory', 'wave print': 'accessory', 'wedding ring': 'accessory',
  'white trim': 'accessory', 'wide sleeves': 'accessory', 'wing print': 'accessory',
  'wrist cuffs': 'accessory', 'wrist scrunchie': 'accessory', 'wristband': 'accessory',
  'yaopei': 'accessory', 'yugake': 'accessory', 'zipper': 'accessory',
  'sash': 'accessory', 'stole': 'accessory', 'shoulder sash': 'accessory',
  'kesa': 'accessory', 'midriff sarashi': 'accessory', 'budget sarashi': 'accessory',
  'undone sarashi': 'accessory', 'tasuki': 'accessory',
  // -- bottom --
  'bell-bottoms': 'bottom', 'bike shorts': 'bottom', 'bloomers': 'bottom',
  'bubble skirt': 'bottom', 'buruma': 'bottom', 'capri pants': 'bottom',
  'chaps': 'bottom', 'cutoff jeans': 'bottom', 'denim shorts': 'bottom',
  'detached pants': 'bottom', 'dolphin shorts': 'bottom', 'gym shorts': 'bottom',
  'high-low skirt': 'bottom', 'high-waist skirt': 'bottom', 'jeans': 'bottom',
  'long skirt': 'bottom', 'lowleg pants': 'bottom', 'lowleg shorts': 'bottom',
  'lowleg skirt': 'bottom', 'micro shorts': 'bottom', 'microskirt': 'bottom',
  'miniskirt': 'bottom', 'overall skirt': 'bottom', 'overskirt': 'bottom',
  'pants': 'bottom', 'pants rolled up': 'bottom', 'pelvic curtain': 'bottom',
  'petticoat': 'bottom', 'plaid skirt': 'bottom', 'pleated shorts': 'bottom',
  'pleated skirt': 'bottom', 'sarong': 'bottom', 'short shorts': 'bottom',
  'shorts': 'bottom', 'shorts under skirt': 'bottom', 'showgirl skirt': 'bottom',
  'skirt': 'bottom', 'suspender skirt': 'bottom', 'tutu': 'bottom',
  'yoga pants': 'bottom', 'hakama': 'bottom', 'hakama pants': 'bottom',
  'hakama short skirt': 'bottom', 'hakama skirt': 'bottom', 'kimono skirt': 'bottom',
  'jodhpurs': 'bottom', 'pajama bottom': 'bottom', 'pajama bottoms': 'bottom',
  'sleep pants': 'bottom',
  // -- bra --
  'sarashi': 'bra', 'chest sarashi': 'bra',
  // -- dress --
  'ao dai': 'dress', 'changpao': 'dress', 'china dress': 'dress',
  'chinese clothes': 'dress', 'dirndl': 'dress', 'furisode': 'dress',
  'hanbok': 'dress', 'hanfu': 'dress', 'japanese clothes': 'dress',
  'kimono': 'dress', 'korean clothes': 'dress', 'layered kimono': 'dress',
  'short kimono': 'dress', 'tangzhuang': 'dress', 'uchikake': 'dress',
  'yukata': 'dress', 'jumpsuit': 'dress', 'short jumpsuit': 'dress',
  'romper': 'dress', 'sweater dress': 'dress', 'competition swimsuit': 'dress',
  'school swimsuit': 'dress', 'slingshot swimsuit': 'dress', 'swimsuit': 'dress',
  'racing suit': 'dress', 'bikesuit': 'dress', 'leotard': 'dress',
  'see-through leotard': 'dress', 'strapless leotard': 'dress', 'bodysuit': 'dress',
  'bodystocking': 'dress', 'unitard': 'dress', 'armored dress': 'dress',
  'sailor dress': 'dress', 'catsuit': 'dress', 'zentai': 'dress', 'wetsuit': 'dress',
  'onesie': 'dress', 'teddy': 'dress', 'teddy (lingerie)': 'dress',
  'babydoll': 'dress', 'chemise': 'dress', 'negligee': 'dress', 'monokini': 'dress',
  'sari': 'dress', 'qipao': 'dress', 'cheongsam': 'dress', 'pinafore': 'dress',
  'playboy bunny': 'dress', 'pajamas': 'dress', 'nightie': 'dress',
  'nightwear': 'dress', 'sleepwear': 'dress', 'kosode': 'dress', 'juban': 'dress',
  'nagajuban': 'dress', 'naga-juban': 'dress',
  // -- footwear --
  'animal slippers': 'footwear', 'ankle boots': 'footwear', 'ankle lace-up': 'footwear',
  'armored boots': 'footwear', 'ballet slippers': 'footwear', 'boots': 'footwear',
  'converse': 'footwear', 'cowboy boots': 'footwear', 'crocs': 'footwear',
  'cross-laced sandals': 'footwear', 'cross-laced shoes': 'footwear',
  'cross-laced slit': 'footwear', 'dress shoes': 'footwear', 'flats': 'footwear',
  'flip-flops': 'footwear', 'footwear ribbon': 'footwear', 'geta': 'footwear',
  'gladiator sandals': 'footwear', 'high heel boots': 'footwear', 'high heels': 'footwear',
  'high tops': 'footwear', 'knee boots': 'footwear', 'lace-up boots': 'footwear',
  'loafers': 'footwear', 'mary janes': 'footwear', 'okobo': 'footwear',
  'open-toe boots': 'footwear', 'open-toe shoes': 'footwear', 'oxfords': 'footwear',
  'platform boots': 'footwear', 'platform heels': 'footwear', 'platform sandals': 'footwear',
  'platform shoes': 'footwear', 'pointy boots': 'footwear', 'pointy shoes': 'footwear',
  'pumps': 'footwear', 'rubber boots': 'footwear', 'sandals': 'footwear',
  'shoes': 'footwear', 'slippers': 'footwear', 'sneakers': 'footwear',
  'sports sandals': 'footwear', 'spurs': 'footwear', 'stiletto heels': 'footwear',
  'thigh boots': 'footwear', 'uwabaki': 'footwear', 'waraji': 'footwear',
  'wedge heels': 'footwear', 'winged boots': 'footwear', 'winged shoes': 'footwear',
  'zouri': 'footwear',
  // -- headwear --
  'balaclava': 'headwear', 'coif': 'headwear', 'crown': 'headwear',
  'diadem': 'headwear', 'forehead protector': 'headwear', 'hachimaki': 'headwear',
  'hair bow': 'headwear', 'hair ribbon': 'headwear', 'hair tie': 'headwear',
  'hairband': 'headwear', 'hat': 'headwear', 'headband': 'headwear',
  'headdress': 'headwear', 'headscarf': 'headwear', 'hijab': 'headwear',
  'maid headdress': 'headwear', 'sweatband': 'headwear', 'tiara': 'headwear',
  'veil': 'headwear', 'wimple': 'headwear', 'hood': 'headwear',
  // -- legwear --
  'ankle socks': 'legwear', 'bobby socks': 'legwear', 'kneehighs': 'legwear',
  'leg warmers': 'legwear', 'leggings': 'legwear', 'loose socks': 'legwear',
  'over-kneehighs': 'legwear', 'pantyhose': 'legwear', 'socks': 'legwear',
  'tabi': 'legwear', 'thighband pantyhose': 'legwear', 'thighhighs': 'legwear',
  'legskin': 'legwear',
  // -- outerwear --
  'cardigan vest': 'outerwear', 'cropped jacket': 'outerwear', 'duffel coat': 'outerwear',
  'fur-trimmed coat': 'outerwear', 'letterman jacket': 'outerwear', 'long coat': 'outerwear',
  'overcoat': 'outerwear', 'safari jacket': 'outerwear', 'suit jacket': 'outerwear',
  'tailcoat': 'outerwear', 'winter coat': 'outerwear', 'yellow raincoat': 'outerwear',
  'bathrobe': 'outerwear', 'sukajan': 'outerwear', 'surcoat': 'outerwear',
  'tabard': 'outerwear', 'poncho': 'outerwear', 'open robe': 'outerwear',
  'see-through raincoat': 'outerwear', 'cassock': 'outerwear', 'cape': 'outerwear',
  'capelet': 'outerwear', 'haori': 'outerwear', 'happi': 'outerwear',
  'mizu happi': 'outerwear', 'hanten (clothes)': 'outerwear',
  'chanchanko (clothes)': 'outerwear', 'peignoir': 'outerwear', 'pelisse': 'outerwear',
  'telogreika': 'outerwear',
  // -- panties --
  'swim briefs': 'panties', 'side-tie bikini bottom': 'panties', 'fundoshi': 'panties',
  'jammers': 'panties', 'loincloth': 'panties',
  // -- top --
  'aran sweater': 'top', 'bandeau': 'top', 'bikini': 'top', 'blouse': 'top',
  'bustier': 'top', 'camisole': 'top', 'collared shirt': 'top', 'compression shirt': 'top',
  'corset': 'top', 'criss-cross halter': 'top', 'crop top': 'top', 'dress shirt': 'top',
  'frilled shirt': 'top', 'halterneck': 'top', 'hoodie': 'top', 'leaf bikini': 'top',
  'lowleg bikini': 'top', 'micro bikini': 'top', 'muneate': 'top',
  'off-shoulder shirt': 'top', 'raglan sleeves': 'top', 'rash guard': 'top',
  'ribbed sweater': 'top', 'shirt': 'top', 'sleeveless shirt': 'top',
  'sleeveless turtleneck': 'top', 'sports bikini': 'top', 'string bikini': 'top',
  'striped shirt': 'top', 'sweater': 'top', 'sweater vest': 'top', 't-shirt': 'top',
  'tank top': 'top', 'tankini': 'top', 'thong bikini': 'top', 'tube top': 'top',
  'tunic': 'top', 'turtleneck sweater': 'top', 'underbust': 'top', 'vest': 'top',
  'waistcoat': 'top', 'pajama top': 'top', 'sleep shirt': 'top',
};

Map<String, String>? _merged;

/// The merged tag → slot table (seed entries win on conflict). Lazily built.
Map<String, String> get tagToSlot {
  final cached = _merged;
  if (cached != null) return cached;
  final m = <String, String>{};
  // Scraped first, then seed overwrites — equivalent to Python's
  // `dict(seed)` then `merged.setdefault(scraped_key, ...)`.
  _scrapedTagToSlot.forEach((k, v) => m[k.toLowerCase()] = v);
  _seedTagToSlot.forEach((k, v) => m[k.toLowerCase()] = v);
  _merged = m;
  return m;
}

Map<String, List<String>>? _candidatesBySlot;

/// Tags grouped by slot, longest-first per slot, for whole-word substring
/// matching in the classifier.
Map<String, List<String>> get candidatesBySlot {
  final cached = _candidatesBySlot;
  if (cached != null) return cached;
  final bySlot = <String, List<String>>{};
  tagToSlot.forEach((tag, slot) {
    (bySlot[slot] ??= <String>[]).add(tag);
  });
  for (final list in bySlot.values) {
    list.sort((a, b) => b.length.compareTo(a.length));
  }
  _candidatesBySlot = bySlot;
  return bySlot;
}

/// Free-text → booru-tag rewrites applied before classification (e.g. "hose" →
/// "pantyhose"). Whole-word match.
const Map<String, String> tagSynonyms = <String, String>{
  'hose': 'pantyhose',
};

/// Modifiers that promote bare `bloomers` from panties → bottom (visible gym
/// bloomers). `buruma` always routes to bottom.
const List<String> bloomersAsBottomHints = <String>[
  'gym',
  'buruma',
  'athletic',
  'sport',
  'sports',
  'beach',
  'swim',
  'pool',
  'school bloomers',
];

/// Closed-front outerwear keywords — an intact instance covers the bra even
/// with no `top` slot beneath. Modern open-front pieces (jacket, cardigan,
/// blazer, coat) are intentionally NOT here.
const List<String> closedFrontOuterwearKeywords = <String>[
  'haori', 'happi', 'kimono', 'yukata', 'hanfu', 'ruqun',
  'robe', 'bathrobe', 'dressing gown',
  'cloak', 'mantle', 'shawl',
  'surcoat', 'tabard',
  'poncho', 'serape',
  'dotera', 'kosode',
];

/// Long closed-front outerwear keywords — these also conceal the pelvis
/// (panties). Short ones (haori, surcoat, tabard, shawl, poncho, mantle) only
/// conceal the chest.
const List<String> longClosedFrontOuterwearKeywords = <String>[
  'kimono',
  'yukata',
  'robe',
  'bathrobe',
  'dressing gown',
  'cloak',
  'hanfu',
  'ruqun',
];
