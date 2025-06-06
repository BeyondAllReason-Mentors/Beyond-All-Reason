return {
	legtriariusheatray = {
		maxacc = 0.02757,
		activatewhenbuilt = true,
		maxdec = 0.02757,
		buildangle = 16384,
		energycost = 8000,
		metalcost = 800,
		buildpic = "legtriariusheatray.DDS",
		buildtime = 11000,
		canmove = true,
		collisionvolumeoffsets = "0 -5 1",
		collisionvolumescales = "34 34 82",
		collisionvolumetype = "CylZ",
		corpse = "DEAD",
		explodeas = "mediumexplosiongeneric",
		floater = true,
		footprintx = 4,
		footprintz = 4,
		idleautoheal = 5,
		idletime = 1800,
		health = 3600,
		speed = 58,
		minwaterdepth = 12,
		movementclass = "BOAT4",
		movestate = 0,
		nochasecategory = "VTOL",
		objectname = "Units/legtriariusheatray.s3o",
		script = "Units/legtriariusheatray.cob",
		seismicsignature = 0,
		selfdestructas = "mediumexplosiongenericSelfd",
		sightdistance = 500,
		sonardistance = 400,
		turninplace = true,
		turninplaceanglelimit = 90,
		turnrate = 280,
		waterline = 0,
		customparams = {
			unitgroup = 'weaponsub',
			model_author = "Mr Bob",
			normaltex = "unittextures/cor_normal.dds",
			subfolder = "CorShips",
		},
		featuredefs = {
			dead = {
				blocking = false,
				category = "corpses",
				collisionvolumeoffsets = "0.0580749511719 -0.062504465332 -0.201034545898",
				collisionvolumescales = "33.2652587891 20.5109710693 79.4415893555",
				collisionvolumetype = "Box",
				damage = 3360,
				featuredead = "HEAP",
				footprintx = 5,
				footprintz = 5,
				height = 4,
				metal = 480,
				object = "Units/corroy_dead.s3o",
				reclaimable = true,
			},
			heap = {
				blocking = false,
				category = "heaps",
				damage = 4032,
				footprintx = 2,
				footprintz = 2,
				height = 4,
				metal = 240,
				object = "Units/cor5X5D.s3o",
				reclaimable = true,
				resurrectable = 0,
			},
		},
		sfxtypes = {
			explosiongenerators = {
				[1] = "custom:barrelshot-medium",
				[2] = "custom:waterwake-small",
				[3] = "custom:bowsplash-small",
			},
			pieceexplosiongenerators = {
				[1] = "deathceg2",
				[2] = "deathceg3",
				[3] = "deathceg4",
			},
		},
		sounds = {
			canceldestruct = "cancel2",
			underattack = "warning1",
			cant = {
				[1] = "cantdo4",
			},
			count = {
				[1] = "count6",
				[2] = "count5",
				[3] = "count4",
				[4] = "count3",
				[5] = "count2",
				[6] = "count1",
			},
			ok = {
				[1] = "shcormov",
			},
			select = {
				[1] = "shcorsel",
			},
		},
		weapondefs = {
			heatroy = {
				areaofeffect = 72,
				avoidfeature = false,
				beamtime = 0.033,
				beamttl = 0.033,
				camerashake = 0.1,
				corethickness = 0.3,
				craterareaofeffect = 72,
				craterboost = 0,
				cratermult = 0,
				beamtime = 0.8,
				beamttl = 0.8,
				edgeeffectiveness = 0.15,
				energypershot = 17,
				explosiongenerator = "custom:heatray-huge",
				firestarter = 90,
				firetolerance = 300,
				impulsefactor = 0,
				intensity = 5,
				laserflaresize = 6,
				name = "Roybeam",
				noselfdamage = true,
				predictboost = 1,
				proximitypriority = -1,
				range = 750,
				reloadtime = 2.2,
				rgbcolor = "1 0.8 0",
				rgbcolor2 = "0.8 0 1",
				soundhitdry = "flamhit1",
				soundhitwet = "sizzle",
				soundstart = "heatray3",
				soundstartvolume = 28,
				soundtrigger = 1,
				thickness = 3.5,
				turret = true,
				weapontype = "BeamLaser",
				weaponvelocity = 1200,
				damage = {
					commanders = 260,
					default = 470,
					vtol = 110,
				},
			},
			mortar = {


				cegtag = "arty-large",


				accuracy = 250,
				areaofeffect = 130,
				avoidfeature = false,
				craterareaofeffect = 130,
				craterboost = 0,
				cratermult = 0,
				edgeeffectiveness = 0.60,
				explosiongenerator = "custom:genericshellexplosion-large",
				gravityaffected = "true",
				hightrajectory = 1,
				impulsefactor = 1.5,
				name = "Mortar",
				noselfdamage = true,
				range = 750,
				reloadtime = 5,
				size = 1.8,
				soundhit = "xplosml3",
				soundhitwet = "splshbig",
				soundstart = "canlite3",
				turret = true,
				weapontype = "Cannon",
				weaponvelocity = 330,
				damage = {
					default = 250,
					subs = 90,
					vtol = 90,
				},
			}
		},
		weapons = {
			[1] = {
				badtargetcategory = "VTOL",
				def = "heatroy",
				onlytargetcategory = "SURFACE",
				fastautoretargeting = true,
			},
			[2] = {
				badtargetcategory = "VTOL",
				def = "mortar",
				onlytargetcategory = "SURFACE",
				fastautoretargeting = true,
			},
		},
	},
}
