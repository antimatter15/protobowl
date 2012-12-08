generateName = ->
	pick = (list) -> 
		n = list.split(',')
		n[Math.floor(n.length * Math.random())]

	adjective = 'twuetwue,aberrant,abstemious,abstruse,academic,adamant,affable,affine,agile,agog,agressive,aloof,ambidextrous,ambiguous,antediluvian,apocryphal,arboreal,arcane,ascetic,assiduous,astute,audacious,auspicious,austere,autoerotic,banal,bellicose,belligerent,benign,bioluminescent,bipolar,blithe,bodacious,boisterous,boorish,breezy,brownian,buoyant,cacophonous,callow,candid,capacious,closed,cognizant,compact,complete,conciliatory,concise,conspicuous,contiguous,contrite,copious,corporeal,counterfeit,covert,crass,credulous,cryptic,cubic,curious,dapper,dazzling,defiant,deistic,deleterious,demented,derisive,dialtory,diaphanous,didactic,disconsolate,discordant,discreet,disheveled,distraught,dogmatic,dormant,drunk,dubious,ebullient,eclectic,edgy,egregious,electric,enigmatic,epicurean,errant,erratic,erroneous,erudite,esoteric,euclidean,euphonious,evanescent,exhaustive,exorbitant,expedient,extant,extemporaneous,extraneous,facetious,facile,fallacious,fatuous,feisty,fervid,flamboyant,flaming,flat,flippant,florid,foppish,foreign,frugal,garrulous,gastric,germane,gloomy,greedy,gregarious,gullible,gutsy,hackneyed,halcyon,hardy,heinous,hirsute,hoary,homothetic,ideal,ignoble,ignominious,imminent,immutable,impassive,imperious,imperturbable,impervious,impetuous,implacable,implicit,impromptu,inadvertent,inane,incessant,inchoate,incipient,incongruous,indefatigable,indelible,indigenous,indolent,indomitable,ineffable,ineluctable,inept,inevitable,inexorable,ingenuous,innocuous,inscrutable,insipid,insolent,insouciant,integral,intransigent,intrepid,invalid,inveterate,invincible,inviolable,irascible,irksome,irradiated,isometric,itinerant,jaundiced,jaunty,jocular,jolly,jovial,judicious,karmic,lachrymose,lackadaisical,languid,lascivious,lethargic,licentious,linear,lithe,loquacious,lucid,lugubrious,lustrous,malleable,marvelous,masochistic,maudlin,maverick,mawkish,melancholy,mellifluous,mendacious,meticulous,metric,mordant,moribund,multifarious,mundane,munificent,mystic,narcissistic,natty,nebulous,nefarious,nonchalant,nostalgic,nuclear,obdurate,obsequious,obstreperous,occult,odious,omnipotent,oneric,onerous,opaque,orthogonal,oscillating,palpable,parsimonious,pedagogical,pedantic,pedestrian,perfunctory,periodic,peripatetic,pernicious,polemic,precise,pristine,profligate,projective,prolific,prolix,puerile,pugnacious,pulsating,punctilious,pusillanimous,quantal,quantum,quirky,quixotic,quizzical,quotidian,rabid,racist,rebellious,recalcitrant,redoubtable,redundant,relativistic,religious,remiss,reserved,reticent,rhetorical,ribald,risible,robotic,sadistic,salacious,salient,salubrious,salutary,sardonic,scientific,scintillating,secular,septic,sinuous,sluggish,somber,soporific,spunky,spurious,stationary,stochastic,succinct,superfluous,supine,symmetric,taciturn,tenebrous,terse,tethered,torpid,transient,trenchant,trite,truculent,turgid,ubiquitous,unctuous,vague,valedictorian,valiant,vehement,verbose,verdant,vituperative,vociferous,warty,wintry,wistful'

	animal = 'aardvark,albatross,algae,alligator,alpaca,amoeba,anglerfish,ant,anteater,antelope,ape,armadillo,axolotl,baboon,badger,barracuda,basilosauridae,bat,bear,beaver,bee,bird,bison,boar,buffalo,butterfly,camel,caribou,cat,caterpillar,cephalopod,chamois,cheetah,chicken,chimpanzee,chinchilla,chipmunk,chough,clam,cobra,cockroach,cod,cormorant,coyote,crab,crane,crocodile,crow,curlew,deer,dinohippus,dinosaur,dog,dogfish,dolphin,donkey,dotterel,dove,dragon,dragonfly,drake,duck,dugong,dunlin,eagle,echidna,eel,effeminate,eland,elephant,elk,emu,equus,falcon,fawn,ferret,finch,fish,flamingo,fly,fox,frog,gaur,gazelle,gecko,gerbil,gibbon,giraffe,gnat,gnu,goat,goldfinch,goldfish,goose,gopher,gopher,gorilla,goshawk,grasshopper,grouse,guanaco,guillemot,gull,hamster,hare,hawk,hedgehog,hen,heron,herring,hippopotamus,hornet,horse,housefly,hummingbird,hyena,ibex,iguana,jackal,jackalope,jaguar,jay,jellyfish,kakapo,kalobatippus,kangaroo,kitten,kitty,koala,kodiak,komodo,kouprey,kudu,lapwing,lark,lemur,leopard,lion,llama,lobster,locust,loris,louse,lynx,lyrebird,macaque,macaw,magpie,mallard,manatee,marten,meerkat,mink,mole,monkey,moose,mosquito,mouse,mule,mushroom,narwhal,neanderthal,newt,nightingale,ocelot,octopus,okapi,opossum,oryx,osprey,ostrich,otter,owl,ox,oyster,panda,panther,paramecium,parrot,partridge,peafowl,pelican,penguin,pheasant,pig,pigeon,platypus,polecat,pony,porcupine,porpoise,possum,pterodactyl,puma,quail,quelea,quetzal,rabbit,raccoon,rail,ram,raptor,rat,rattlesnake,raven,reindeer,rhinoceros,rook,ruff,salamander,salmon,sandpiper,sardine,scorpion,seahorse,seal,seastar,serval,shark,sheep,shrew,skunk,snail,snake,spider,squid,squirrel,starling,stingray,stinkbug,stork,swallow,swan,tapir,tarsier,termite,tiger,toad,tortoise,trout,turkey,turtle,unicorn,ursine,viper,vulture,wallaby,walrus,warthog,wasp,weasel,werewolf,whale,wolf,wolverine,wombat,woodcock,woodpecker,worm,wren,yak,zebra'
	pick(adjective) + " " + pick(animal)

generatePage = ->
	pick = (list) -> 
		n = list.split(',')
		n[Math.floor(n.length * Math.random())]

	people = 'mayhaps,actor,actress,alien,astronaut,astronaut,astronomer,batman,ben,cats,celebrity,cherenkov,chicken,colbert,copernicus,dali,dirac,einstein,entomologist,erdos,etymologist,fermi,feynman,huxley,irving,kepler,kirk,kitten,lemon,mold,oppenheimer,panda,picard,pinkman,plague,police,robot,sagan,sailor,scatologist,schrodinger,scientist,shakespeare,sherlock,stallman,superhero,traitor,whale,'
	verb = 'afflicting,around,arousing,arresting,cloning,dating,defrauding,destroying,discarding,drinking,eating,eloping,enveloping,evoking,faking,feeding,feeling,feigning,flaunting,in,jumping,kicking,licking,near,observing,on,painting,petting,pronouncing,protecting,protesting,rappelling,scrambling,searching,sleeping,stalking,stroking,studying,tasting,throwing,touching,vomiting,voting'
	noun = 'airplane,allergies,asylum,beard,book,brick,canteen,chicken,cloud,cow,drugs,earth,earwax,egg,electorate,elevator,endorphins,facade,feather,friend,helicopter,house,jupiter,lamp,mars,meat,mercury,moon,mountain,neptune,pants,paper,paris,pebble,planet,plant,pluto,pony,printer,rhinoceros,rock,saturn,scandal,school,skeleton,staple,sunscreen,toilet,trampoline,tree,turd,uranus,venus,water,wikipedia,'
	pick(people) + "-" + pick(verb) + "-" + pick(noun)

exports.generatePage = generatePage if exports?
exports.generateName = generateName if exports?