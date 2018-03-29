if GetLocale() == "esES" then
qcLocalize = {
	ABYSSALDEPTHS = "Profundidades Abisales",
	AHNKAHETTHEOLDKINGDOM = "Ahn'Kalet: El Antiguo Reino",
	AHNQIRAJ = "Ahn'Qiraj",
	AHNQIRAJTHEFALLENKINGDOM = "Ahn'Qiraj: el Reino Ca�do",
	ALCHEMY = "Alquimia",
	ALTERACVALLEY = "Valle de Alterac",
	ARATHIBASIN = "Cuenca de Arathi",
	ARATHIHIGHLANDS = "Tierras Altas de Arathi",
	ARCHAEOLOGY = "Arqueolog�a",
	ASHENVALE = "Vallefresno",
	ASHRAN = "Ashran", -- Requires localization
	ASSAULTONTHEDARKPORTAL = "Assault on the Dark Portal", -- Requires localization
	AUCHENAICRYPTS = "Criptas Auchenai",
	AUCHINDOUN = "Auchindoun",
	AZEROTH = "Azeroth", -- Requires localization
	AZJOLNERUB = "Azjol-Nerub",
	AZSHARA = "Azshara",
	AZUREMYSTISLE = "Isla Bruma Azur",
	BADLANDS = "Tierras Inh�spitas",
	BARADINHOLD = "Basti�n de Baradin",
	BATTLEGROUNDS = "Campos de Batalla",
	BATTLEPETS = "Duelo de mascotas",
	BLACKFATHOMDEEPS = "Cavernas de Brazanegra",
	BLACKROCKCAVERNS = "Cavernas Roca Negra",
	BLACKROCKDEPTHS = "Profundidades de Roca Negra",
	BLACKROCKFOUNDRY = "Blackrock Foundry", -- Requires localization
	BLACKROCKSPIRE = "Cumbre de Roca Negra",
	BLACKSMITHING = "Herrer�a",
	BLACKTEMPLE = "Templo oscuro",
	BLACKWINGDESCENT = "Descenso de Alanegra",
	BLACKWINGLAIR = "Guarida de Alanegra",
	BLADESEDGEMOUNTAINS = "Monta�as Filospada",
	BLASTEDLANDS = "Tierras Devastadas",
	BLOODMAULSLAGMINES = "Bloodmaul Slag Mines", -- Requires localization
	BLOODMYSTISLE = "Isla Bruma de Sangre",
	BOREANTUNDRA = "Tundra Boreal",
	BRAWLERSGUILD = "Brawler's Guild", -- Requires localization
	BREWFEST = "Fiesta de la Cerveza",
	BREWMOONFESTIVAL = "Brewmoon Festival", -- Requires localization
	BURNINGSTEPPES = "Estepas Ardientes",
	CAVERNSOFTIME = "Cavernas del tiempo",
	CENTRALKALIMDOR = "Central Kalimdor", -- Requires localization
	CHILDRENSWEEK = "Semana de los ni�os",
	CLASSES = "Clases",
	CLASSQUESTS = "Misiones de clase",
	CLEARUPDATECACHE = "Borrar cach� de actualizaci�n",
	COILFANGRESERVOIR = "Reserva Colmillo Torcido",
	COMBINEDMAPANDQUESTFILTERS = "Filtros combinados de misiones y mapas",
	CONFIGSUBTITLE = "Estas opciones permiten modificar c�mo Quest Completist maneja y filtra los datos",
	CONFIGTITLE = "Quest Completist - Configuraci�n",
	CONTINENTS = "Continentes",
	COOKING = "Cocina",
	CRYSTALSONGFOREST = "Bosque Canto de Cristal",
	DALARAN = "Dalaran",
	DARKMOONFAIRE = "Feria de la Luna Negra",
	DARKSHORE = "Costa Oscura",
	DARNASSUS = "Darnassus",
	DAYOFTHEDEAD = "Festividad de los Muertos",
	DEADWINDPASS = "Paso de la Muerte",
	DEATHKNIGHT = "Caballero de la Muerte",
	DEEPHOLM = "Infralar",
	DEEPRUNTRAM = "Tranv�a Subterr�neo",
	DESOLACE = "Desolace",
	DIREMAUL = "La Masacre",
	DRAENOR = "Draenor", -- Requires localization
	DRAGONBLIGHT = "Cementerio de Dragones",
	DRAGONSOUL = "Alma de Drag�n",
	DRAKTHARONKEEP = "Fortaleza de Drak'Tharon",
	DREADWASTES = "Desierto del Pavor",
	DRUID = "Druida",
	DUNGEONSANDRAIDS = "Mazmorras y Bandas",
	DUNMOROGH = "Dun Morogh",
	DUROTAR = "Durotar",
	DUSKWOOD = "Bosque Oscuro",
	DUSTWALLOWMARSH = "Marjal Revolcafango",
	EASTERNKINGDOMS = "Reinos del Este",
	EASTERNPLAGUELANDS = "Tierras de la Peste del Este",
	ELEMENTALBONDS = "V�nculos elementales",
	ELWYNNFOREST = "Bosque de Elwynn",
	ENCHANTING = "Encantamiento",
	ENDTIME = "Fin de los D�as",
	ENGINEERING = "Ingenieria",
	EVERSONGWOODS = "Bosque Canci�n Eterna",
	EYEOFTHESTORM = "Ojo de la Tormenta",
	FELWOOD = "Frondavil",
	FERALAS = "Feralas",
	FIRELANDS = "Tierras de Fuego",
	FIRELANDSINVASION = "Invasi�n de las Tierras de Fuego",
	FIRSTAID = "Primeros Auxilios",
	FISHING = "Pesca",
	FROSTFIRERIDGE = "Frostfire Ridge", -- Requires localization
	GARRISONCAMPAIGN = "Garrison Campaign", -- Requires localization
	GARRISONSUPPORT = "Garrison Support", -- Requires localization
	GATEOFTHESETTINGSUN = "Gate of the Setting Sun", -- Requires localization
	GHOSTLANDS = "Tierras Fantasma",
	GILNEAS = "Gilneas",
	GILNEASCITY = "Ciudad de Gilneas",
	GNOMEREGAN = "Gnomeregan",
	GORGROND = "Gorgrond", -- Requires localization
	GREENSTONEVILLAGE = "Greenstone Village", -- Requires localization
	GRIMBATOL = "Grim Batol",
	GRIMRAILDEPOT = "Grimrail Depot", -- Requires localization
	GRIZZLYHILLS = "Colinas Pardas",
	GRUULSLAIR = "Guarida de Gruul",
	GUNDRAK = "Gundrak",
	HALLOWSEND = "Halloween",
	HALLSOFLIGHTNING = "C�maras de Rel�mpagos",
	HALLSOFORIGINATION = "C�maras de los Or�genes",
	HALLSOFREFLECTION = "C�maras de Reflexi�n",
	HALLSOFSTONE = "C�maras de Piedra",
	HARVESTFESTIVAL = "Festival de la Cosecha",
	HELLFIRECITADEL = "Ciudadela del Fuego Infernal",
	HELLFIREPENINSULA = "Pen�nsula del Fuego Infernal",
	HELLFIRERAMPARTS = "Murallas del Fuego Infernal",
	HERBALISM = "Herborister�a",
	HIDECOMPLETEDQUESTS = "Ocultar misiones completadas",
	HIDEINPROGRESSQUESTS = "Ocultar misiones en curso",
	HIDELOWLEVELQUESTS = "Ocultar misiones de nivel bajo",
	HIDENONACTIVESEASONALQUESTS = "Esconder misiones de eventos inactivos",
	HIDEOTHERFACTIONQUESTS = "Esconder otras misiones de facci�n",
	HIDEOTHERPROFESSIONQUESTS = "Esconder otras misiones de profesi�n",
	HIDEOTHERRACEANDCLASSQUESTS = "Esconder otras misiones de clase/raza",
	HIGHMAUL = "Highmaul", -- Requires localization
	HILLSBRADFOOTHILLS = "Laderas de Trabalomas",
	HOUROFTWILIGHT = "Hora del Crepusculo",
	HOWLINGFJORD = "Fiordo Aquilonal",
	HROTHGARSLANDING = "Desembarco de Hrothgar",
	HUNTER = "Cazador",
	HYJALSUMMIT = "Cima Hyjal",
	ICECROWN = "Corona de Hielo",
	ICECROWNCITADEL = "Ciudadela de la Corona de Hielo",
	INSCRIPTION = "Inscripci�n",
	IRONDOCKS = "Iron Docks", -- Requires localization
	IRONFORGE = "Forjaz",
	ISLEOFCONQUEST = "Isla de la Conquista",
	ISLEOFGIANTS = "Isle of Giants", -- Requires localization
	ISLEOFQUELDANAS = "Isla de Quel'Danas",
	ISLEOFTHUNDER = "Isle of Thunder", -- Requires localization
	JADETEMPLEGROUNDS = "Jade Temple Grounds", -- Requires localization
	JEWELCRAFTING = "Joyer�a",
	KALIMDOR = "Kalimdor",
	KARAZHAN = "Karazhan",
	KELPTHARFOREST = "Bosque Kelp'thar",
	KEZAN = "Kezan",
	KHAZMODAN = "Khaz Modan", -- Requires localization
	KRASARANGWILDS = "Espesura Krasarang",
	KUNLAISUMMIT = "Cima Kun-Lai",
	LANDFALL = "Landfall", -- Requires localization
	LEATHERWORKING = "Peleteria",
	LEGENDARY = "Legendario",
	LOCHMODAN = "Loch Modan",
	LORDAERON = "Lordaeron", -- Requires localization
	LOSTCITYOFTHETOLVIR = "Ciudad Perdida de los Tol'vir",
	LOVEISINTHEAIR = "Amor en el aire",
	LUNARFESTIVAL = "Festival Lunar",
	MAGE = "Mago",
	MAGISTERSTERRACE = "Bancal del Magister",
	MAGTHERIDONSLAIR = "Guarida de Magtheridon",
	MANATOMBS = "Tumbas de Man�",
	MAPFILTERS = "Filtros de mapa",
	MARAUDON = "Maraudon",
	MIDSUMMERFIREFESTIVAL = "Festival de Fuego del Solsticio de Verano",
	MINING = "Miner�a",
	MISCELLANEOUS = "Miscel�nea",
	MOGUSHANPALACE = "Mogu'shan Palace", -- Requires localization
	MOGUSHANVAULTS = "C�maras Mogu'shan",
	MOLTENCORE = "N�cleo de Magma",
	MOLTENFRONT = "Frente de Magma",
	MONK = "Monje",
	MOONGLADE = "Claro de la Luna",
	MOUNTHYJAL = "Monte Hyjal",
	MULGORE = "Mulgore",
	NAGRAND = "Nagrand",
	NAXXRAMAS = "Naxxramas",
	NETHERSTORM = "Tormenta Abisal",
	NEWYEARSEVE = "Nochevieja",
	NOBLEGARDEN = "Jard�n Noble",
	NORTHERNBARRENS = "Bald�os del Norte",
	NORTHERNKALIMDOR = "Northern Kalimdor", -- Requires localization
	NORTHERNSTRANGLETHORN = "Norte de la Vega de Tuercespina",
	NORTHREND = "Rasganorte",
	OLDHILLSBRADFOOTHILLS = "Antiguas Laderas de Trabalomas",
	ONYXIASLAIR = "Guarida de Onyxia",
	OPTIONS = "Opciones",
	ORGRIMMAR = "Orgrimmar",
	OUTLAND = "Terrallende",
	PALACEOFTHEHEAVENS = "Palacio Mogu'shan",
	PALADIN = "Palad�n",
	PANDARENBREWMASTERS = "Pandaren Brewmasters", -- Requires localization
	PANDARENCAMPAIGN = "Pandaren Campaign", -- Requires localization
	PANDARIA = "Pandaria",
	PEAKOFSERENITY = "Peak of Serenity", -- Requires localization
	PERFORMSERVERQUERY = "Enviar consulta al servidor...",
	PILGRIMSBOUNTY = "Generosidad del Peregrino",
	PITOFSARON = "Foso de Saron",
	PRIEST = "Sacerdote",
	PROFESSIONS = "Profesiones",
	PROVINGGROUNDS = "Proving Grounds", -- Requires localization
	QUERYREQUESTED = "Se ha enviado una consulta al servidor...",
	QUESTLISTFILTERS = "Filtros de lista de misiones",
	QUESTSFOUND = "%d misiones encontradas",
	RAGEFIRECHASM = "Sima �gnea",
	RAIDS = "Bandas",
	RAZORFENDOWNS = "Zah�rda Rajacieno",
	RAZORFENKRAUL = "Horado Rajacieno",
	REDRIDGEMOUNTAINS = "Monta�as Crestagrana",
	REGIONS = "Regions", -- Requires localization
	RIDING = "Riding", -- Requires localization
	ROGUE = "Picaro",
	RUINSOFAHNQIRAJ = "Ruinas de Ahn'Qiraj",
	RUINSOFGILNEAS = "Ruinas de Gilneas",
	RUINSOFGILNEASCITY = "Ruinas de la Ciudad de Gilneas",
	SCARLETHALLS = "Scarlet Halls", -- Requires localization
	SCARLETMONASTERY = "Monasterio Escarlata",
	SCENARIO = "Scenario", -- Requires localization
	SCHOLOMANCE = "Scholomance",
	SEARINGGORGE = "La Garganta de Fuego",
	SEASONAL = "Vacacionales",
	SERPENTSHRINECAVERN = "Caverna Santuario Serpiente",
	SETHEKKHALLS = "Salas Sethekk",
	SHADOPANMONASTERY = "Monasterio Shado-Pan",
	SHADOWFANGKEEP = "Castillo de Colmillo Oscuro",
	SHADOWLABYRINTH = "Laberinto de las Sombras",
	SHADOWMOONBURIALGROUNDS = "Shadowmoon Burial Grounds", -- Requires localization
	SHADOWMOONVALLEY = "Valle Sombraluna",
	SHAMAN = "Cham�n",
	SHATTRATHCITY = "Ciudad de Shattrath",
	SHIMMERINGEXPANSE = "Extensi�n Bru�ida",
	SHOLAZARBASIN = "Cuenca de Sholazar",
	SHOWMAPICONS = "Mostrar iconos del mapa",
	SIEGEOFNIUZAOTEMPLE = "Asedio del Templo de Niuzao",
	SIEGEOFORGRIMMAR = "Siege of Orgrimmar", -- Requires localization
	SILITHUS = "Silithus",
	SILVERMOONCITY = "Ciudad de Lunargenta",
	SILVERPINEFOREST = "Bosque de Arg�nteos",
	SILVERSHARDMINES = "Minas Lonjaplata",
	SKETTIS = "Skettis", -- Requires localization
	SKINNING = "Desuello",
	SKYREACH = "Skyreach", -- Requires localization
	SORTALPHA = "Ordenar: alfab�ticamente",
	SORTLEVEL = "Ordenar: por nivel",
	SOUTHERNBARRENS = "Bald�os del Sur",
	SOUTHERNKALIMDOR = "Southern Kalimdor", -- Requires localization
	SPECIAL = "Especial",
	SPECIALS = "Especiales",
	SPIREOFLIGHT = "Spire of Light", -- Requires localization
	SPIRESOFARAK = "Spires Of Arak", -- Requires localization
	STONETALONMOUNTAINS = "Sierra Espol�n",
	STORMSHIELD = "Stormshield", -- Requires localization
	STORMSHIELDSTRONGHOLD = "Stormshield Stronghold", -- Requires localization
	STORMSTOUTBREWERY = "Cervecer�a del Trueno",
	STORMWINDCITY = "Ciudad de Ventormenta",
	STRANDOFTHEANCIENTS = "Playa de los Ancestros",
	STRANGLETHORNVALE = "Vega de Tuercespina",
	STRATHOLME = "Stratholme",
	SUNKENTEMPLE = "Templo Sumergido",
	SUNSTRIDERISLE = "Sunstrider Isle", -- Requires localization
	SUNWELLPLATEAU = "Meseta de La Fuente del Sol",
	SWAMPOFSORROWS = "Pantano de las Penas",
	TAILORING = "Sastrer�a",
	TALADOR = "Talador", -- Requires localization
	TANAANJUNGLE = "Tanaan Jungle", -- Requires localization
	TANARIS = "Tanaris",
	TELDRASSIL = "Teldrassil",
	TEMPESTKEEP = "Castillo de la Tempestad",
	TEMPLEOFAHNQIRAJ = "Templo de Ahn'Qiraj",
	TEMPLEOFKOTMOGU = "Templo de Kotmogu",
	TEMPLEOFTHEJADESERPENT = "Temple of the Jade Serpent", -- Requires localization
	TEMPLEOFTHEREDCRANE = "Templo de la Grulla Roja",
	TEROKKARFOREST = "Bosque de Terokkar",
	THEARBORETUM = "The Arboretum", -- Requires localization
	THEARCATRAZ = "El Arcatraz",
	THEBASTIONOFTWILIGHT = "El Basti�n del Crep�sculo",
	THEBATTLEFORGILNEAS = "La Batalla por Gilneas",
	THEBLACKMORASS = "La Ci�naga Negra",
	THEBLOODFURNACE = "El Horno de Sangre",
	THEBOTANICA = "El Invern�culo",
	THECAPEOFSTRANGLETHORN = "El Cabo de Tuercespina",
	THECULLINGOFSTRATHOLME = "La Matanza de Stratholme",
	THEDEADMINES = "Las Minas de la Muerte",
	THEEVERBLOOM = "The Everbloom", -- Requires localization
	THEEXODAR = "El Exodar",
	THEEYE = "El Castillo de la Tempestad",
	THEEYEOFETERNITY = "El Ojo de la Eternidad",
	THEFORGEOFSOULS = "La Forja de Almas",
	THEGATEOFTHESETTINGSUN = "Puerta del Sol Poniente",
	THEHALFHILLMARKET = "El Mercado de Alcor",
	THEHINTERLANDS = "Tierras del Interior",
	THEJADEFOREST = "Bosque de Jade",
	THELOSTISLES = "Las Islas Perdidas",
	THEMAELSTROM = "La Vor�gine",
	THEMECHANAR = "El Mechanar",
	THENEXUS = "El Nexo",
	THEOBSIDIANSANCTUM = "El Sagrario Obsidiana",
	THEOCULUS = "El Oculus",
	THERUBYSANCTUM = "El Sagrario Rub�",
	THESHATTEREDHALLS = "Las Salas Arrasadas",
	THESLAVEPENS = "Recinto de los Esclavos",
	THESTEAMVAULT = "La C�mara de Vapor",
	THESTOCKADE = "Las Mazmorras",
	THESTONECORE = "N�cleo P�treo",
	THESTORMPEAKS = "Cumbres Tormentosas",
	THETEMPLEOFTHEJADESERPENT = "Templo del Drag�n de Jade",
	THEUNDERBOG = "La Soti�naga",
	THEVEILEDSTAIR = "La Escalera Velada",
	THEVIOLETHOLD = "Basti�n Violeta",
	THEVORTEXPINNACLE = "La Cumbre del V�rtice",
	THEWANDERINGISLE = "La Isla Errante",
	THEZANDALARI = "Los Zandalari",
	THOUSANDNEEDLES = "Mil Agujas",
	THRONEOFTHEFOURWINDS = "Trono de los Cuatro Vientos",
	THRONEOFTHETIDES = "Trono de las Mareas",
	THRONEOFTHUNDER = "Throne of Thunder", -- Requires localization
	THUNDERBLUFF = "Cima del Trueno",
	TIMELESSISLE = "Timeless Isle", -- Requires localization
	TIRISFALGLADES = "Claros de Tirisfal",
	TOLBARAD = "Tol Barad",
	TOLBARADPENINSULA = "Pen�nsula de Tol Barad",
	TOURNAMENT = "Torneo",
	TOWNLONGSTEPPES = "Estepas de Tong Long",
	TRIALOFTHECHAMPION = "Prueba del Campe�n",
	TRIALOFTHECRUSADER = "Prueba del Cruzado",
	TWILIGHTHIGHLANDS = "Tierras Altas Crepusculares",
	TWINPEAKS = "Cumbres Gemelas",
	ULDAMAN = "Uldaman",
	ULDUAR = "Ulduar",
	ULDUM = "Uldum",
	UNDERCITY = "Entra�as",
	UNGAINGOO = "Unga Ingoo", -- Requires localization
	UNGOROCRATER = "Cr�ter de Un'Goro",
	UPPERBLACKROCKSPIRE = "Upper Blackrock Spire", -- Requires localization
	UTGARDEKEEP = "Fortaleza de Utgarde",
	UTGARDEPINNACLE = "Pin�culo de Utgarde",
	VALEOFETERNALBLOSSOMS = "Valle Flor Eterna",
	VALLEYOFTHEFOURWINDS = "Valle de los Cuatro Vientos",
	VASHJIR = "Vashj'ir",
	VAULTOFARCHAVON = "C�mara de Archavon",
	WAILINGCAVERNS = "Cuevas de los Lamentos",
	WARLOCK = "Brujo",
	WARRIOR = "Guerrero",
	WARSONGGULCH = "Garganta Grito de Guerra",
	WARSPEAR = "Warspear", -- Requires localization
	WARSPEAROUTPOST = "Warspear Outpost", -- Requires localization
	WELLOFETERNITY = "Pozo de la Eternidad",
	WESTERNPLAGUELANDS = "Tierras de la Peste del Oeste",
	WESTFALL = "P�ramos de Poniente",
	WETLANDS = "Los Humedales",
	WINTERGRASP = "Conquista del Invierno",
	WINTERSPRING = "Cuna del Invierno",
	WINTERVEIL = "Festival de Invierno",
	WORLDEVENTS = "Eventos del Mundo",
	ZANGARMARSH = "Marisma de Zangar",
	ZULAMAN = "Zul'Aman",
	ZULDRAK = "Zul'Drak",
	ZULFARRAK = "Zul'Farrak",
	ZULGURUB = "Zul'Gurub",
THEBROKENISLES = "The Broken Isles",
	THEDREAMGROVE = "The Dreamgrove",
	AZSUNA = "Azsuna",
	HIGHMOUNTAIN = "Highmountain",
	STORMHEIM = "Stormheim",
	SURAMAR = "Suramar",
	VALSHARAH = "Val'sharah",
	DEMONHUNTER = "Demon Hunter",
	CONTESTCOMMING = "Contest comming shows wrong zone",
	HALLOFTHEGUARDIAN = "Hall of the Guardian",
	MARDUMTHESHATTEREDABYSS = "Mardum, the Shattered Abyss",
	NETHERLIGHTTEMPLE = "Netherlight Temple",
	SKYHOLD = "Skyhold",
	THEHEARTOFAZERTH = "The Heart of Azeroth",
	THEWANDERINGISLE = "The Wandering Isle Monk",
	TRUESHOTLODGE = "Trueshot Lodge Hunter",
	ACHERUSTHEEBONHOLD = "Acherus: The Ebon Hold",
	BLACKOOKHOLD = "Black Rook Hold",
	COURTOFSTARS = "Court of Stars",
	DARKHEARTTHICKET	 = "Darkheart Thicket",
	EYEOFAZSHARA = "	Eye of Azshara",
	HALLSOFVALOR = "Halls of Valor",
	MAWOFSOULS = "Maw of Souls",
	NELTHARIONSLAIR = "Neltharion's Lair",
	THEARCWAY = "The Arcway", 
	VAULTOFTHEWARDENS = "Vault of the Wardens",
	VIOLETHOLD = "Violet Hold",
	THEEMERALDNIGHTMARE = "The Emerald Nightmare",
	TRIALOFVALOR = "Trial of Valor",
	THENIGHTHOLD = "	The Nighthold",
	BROKENSHORE = "Broken Shore",	
	LEGIONUNCATEQUEST = "Legion Uncategorized Quests",
	CATHEDRALOFETERNALNIGHT = "Cathedral of Eternal Night", 
	RETURNTOKARAZHAN = "Return to Karazhan",
 	TOMBOFSARGERAS = "Tomb of Sargeras",
	KROKUUN = "Krokuun",
	ANTORANWASTES = "Antoran Wastes",
	ARGUS = "Argus",
	MACAREE = "Mac'Aree",
	DREADSCARRIFT = "Dreadscar Rift",
	ANTORUSTHEBURNINGTHRONE = "Antorus, the Burning Throne",
	HELHEIM = "Helheim",
	THESEATOFTHETRIUMVIRATE = "The Seat Of The Triumvirate",
	EMERALDDREAMWAY = "Emerald Dreamway",
	BFA = "Battle For Azeroth",
	BFAUNCATEQUEST = "BFA Uncategorized Quests",
	ZANDALAR = "Zandalar",
	KULTIRAS = "Kul Tiras",
	THUNDERTOTEM = "Thunder Totem",
}

end