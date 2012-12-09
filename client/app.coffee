#= require ./lib/modernizr.js
#= require ./lib/bootstrap.js
#= require ./lib/time.coffee
#= require plugins.coffee
#= require annotations.coffee
#= require buttons.coffee
#= require render.coffee
#= require auth.coffee
#= require ../shared/player.coffee
#= require ../shared/room.coffee

do ->
	try
		t = new Date protobowl_app_build
		# todo: add padding to minute so it looks less weird
		$('#version').text "#{t.getMonth()+1}/#{t.getDate()}/#{t.getFullYear() % 100} #{t.getHours()}:#{(t.getMinutes()/100).toFixed(2).slice(2)}"


# asynchronously load the other code which doesn't need to be there on startup necessarily
initialize_offline = (cb) ->	
	$.ajax {
		url: '/offline.js',
		cache: true,
		dataType: 'script',
		success: cb
	}


offline_startup = ->
	initialize_offline ->
		room.__listeners.joined {
			id: 'offline',
			name: 'offline user'
		}
		
		room.sync(3)
		me.verb 'joined the room'

		load_bookmarked_questions()

	setTimeout ->
		chatAnnotation({text: 'Feeling lonely offline? Just say "I\'m Lonely" and talk to me!' , user: '__protobot', done: true})
	, 30 * 1000

sock = null
has_connected = false

online_startup = ->
	# if !url and location.hostname is 'protobowl.com'
	# 	url = 'https://protobowl.jitsu.com:443/'
	# 	# try the secure one when on nodejitsu to evade school proxies

	sock = io.connect location.hostname, {
		"connect timeout": 4000
	}

	sock.on 'connect', ->
		has_connected = true
		$('.disconnect-notice').slideUp()
		# allow the user to reload/disconnect/reconnect
		$('#reload, #disconnect, #reconnect').hide()
		$('#disconnect').show()

		load_bookmarked_questions()

		me.disco { old_socket: localStorage.old_socket, version: 5 } # tell the server the client version to allow the server to disconnect

	sock.on 'disconnect', ->
		$('#reload, #disconnect, #reconnect').hide()
		$('#reconnect').show()
		room.attempt = null if room.attempt?.user isnt me.id # get rid of any buzzes
		line = $('<div>').addClass 'alert alert-error'
		line.append $('<p>').append("You were ", $('<span class="label label-important">').text("disconnected"), 
				" from the server for some reason. ", $('<em>').text(new Date))
		line.append $('<p>').append("This may be due to a drop in the network 
				connectivity or a malfunction in the server. The client will automatically 
				attempt to reconnect to the server and in the mean time, the app has automatically transitioned
				into <b>offline mode</b>. You can continue playing alone with a limited offline set
				of questions without interruption. However, you might want to try <a href=''>reloading</a>.")
		addImportant $('<div>').addClass('log disconnect-notice').append(line)

if io?
	online_startup()

	setTimeout ->
		$('#slow').slideDown() if !has_connected
	, 1000 * 3

	setTimeout initialize_offline, 1000
else
	offline_startup()

load_bookmarked_questions = ->
	bookmarks = []
	try
		bookmarks = JSON.parse(localStorage.bookmarks)
	for question in bookmarks
		bundle = create_bundle(question)
		bundle.find('.readout').hide()
		$('#history').prepend bundle

# stress test da servs
# setTimeout ->
# 	location.href = "/#{Math.random().toString().slice(3)}"
# , 1000

connected = -> sock? and sock.socket.connected

class QuizPlayerClient extends QuizPlayer
	online: -> @online_state

class QuizPlayerSlave extends QuizPlayerClient
	
	# encapsulate is such a boring word, well actually, it's pretty cool
	# but you should be allowed to envelop actions like captain kirk 
	# does to a mountain.

	envelop_action: (name) ->
		master_action = this[name]
		this[name] = (data, callback) ->
			if connected()
				sock.emit(name, data, callback)
			else
				# It matters not how strait the gate,
				# How charged with punishments the scroll.
				# I am the master of my fate:
				# I am the captain of my soul. 

				# TODO: possibly delay this call until certain offline component is loaded
				master_action.call(this, data, callback)

	constructor: (room, id) ->
		super(room, id)
		# the difference between local-exec and remote-exec code is a little weird
		# i don't exactly like the concept of needing to maintain an exception list
		# and it would have been probably a good idea if it was instead something like
		# functions starting with get_ are treated as local-exec, but I dont feel like
		# propagating a breaking change 

		blacklist = ['envelop_action', 'score', 'online', 'active', 'authorized']
		@envelop_action name for name, method of this when typeof method is 'function' and name not in blacklist




class QuizRoomSlave extends QuizRoom
	# dont know what to change
	emit: (name, data) ->
		@__listeners[name](data)

	constructor: (name) ->
		super(name)
		@__listeners = {}

	load_questions: (cb) ->
		if load_questions?
			load_questions cb
		else
			setTimeout =>
				@load_questions cb
			, 100

	check_answer: (attempt, answer, question) -> checkAnswer(attempt, answer, question) 

	get_parameters: (type, difficulty, cb) ->
		@load_questions ->
			get_parameters(type, difficulty, cb)

	count_questions: (type, difficulty, category, cb) ->
		@load_questions ->
			count_questions(type, difficulty, category, cb)

	get_question: (cb) ->
		@load_questions =>
			category = (if @category is 'custom' then @distribution else @category)
			get_question @type, @difficulty, category, (question) =>
				cb(question || error_question)


room = new QuizRoomSlave()
me = new QuizPlayerSlave(room, 'temporary')

# look at all these one liner events!
listen = (name, fn) ->
	sock.on name, fn if sock?
	room.__listeners[name] = fn

# probably should figure out some more elegant way to do things, but then again
# these things hardly actually need to be frequently added - it's mostly hacks
listen 'echo', (data, fn) -> fn 'alive'
listen 'application_update', -> applicationCache.update() if applicationCache?
listen 'force_application_update', -> $('#update').data('force', true); applicationCache.update()
listen 'redirect', (url) -> window.location = url
listen 'alert', (text) -> window.alert text
listen 'chat', (data) -> chatAnnotation data
listen 'log', (data) -> verbAnnotation data
listen 'debug', (data) -> logAnnotation data
listen 'sync', (data) -> synchronize data
listen 'throttle', (data) ->
	createAlert $('.bundle.active'), 'Throttled', "The server is ignoring you for a while because you've been doing too many things too quickly. "

listen 'rename_user', ({old_id, new_id}) ->
	if me.id is old_id
		me.id = new_id
		room.users[me.id] = me
	$(".user-#{old_id}").removeClass("user-#{old_id}").addClass("user-#{new_id}")
	delete room.users[old_id]

listen 'delete_user', (id) ->
	console.log 'deleting user', id
	delete room.users[id]
	renderUsers()

listen 'joined', (data) ->
	me.id = data.id
	room.users[me.id] = me

	me.name = data.name

	if me.id[0] != '_'
		if localStorage.username
			if !data.existing
				setTimeout ->
					me.name = localStorage.username
					me.set_name me.name
					$('#username').val me.name
				, 137 # for some reason there's this odd bug where
				# if i dont have a timeout, this doesn't update the
				# stuff at all, so I really don't understand why
				# and moreover, I think the fine structure constant
				# is an appropriate metaphor for that non-understanding
		else
			localStorage.username = data.name

	$('#slow').slideUp()

	$('.actionbar button').disable false

	$('#username').val me.name
	$('#username').disable false




sync_offsets = []
latency_log = []
last_freeze = -1

synchronize = (data) ->
	blacklist = ['real_time', 'users']
	
	sync_offsets.push +new Date - data.real_time
	compute_sync_offset()
	
	room[attr] = val for attr, val of data when attr not in blacklist

	if connected()
		if 'timing' of data or room.__last_rate isnt room.rate
			cumsum = (list, rate) ->
				sum = 0 #start nonzero, allow pause before rendering
				for num in [5].concat(list).slice(0, -1)
					sum += Math.round(num) * rate #always round!
			room.cumulative = cumsum room.timing, room.rate
			room.__last_rate = room.rate

		if  'users' of data
			# keep the number of people in the leaderboard at a manageable number
			if (1 for u of room.users).length > data.users.length + 5
				room.users = {}

			user_blacklist = ['id']
			for user in data.users
				if user.id is me.id
					# console.log "it's me, mario!"
					room.users[user.id] = me
				else
					unless user.id of room.users
						room.users[user.id] = new QuizPlayerClient(room, user.id)

				for attr, val of user when attr not in user_blacklist
					room.users[user.id][attr] = val

	renderParameters() if 'difficulties' of data

	renderUpdate()

	renderPartial()

	
	if last_freeze isnt room.time_freeze
		last_freeze = room.time_freeze
		variable = (if room.attempt then 'starts' else 'stops')
		del = room.time_freeze - room.begin_time
		i = 0
		i++ while del > room.cumulative[i]
		starts = ($('.bundle.active').data(variable) || [])
		starts.push(i - 1) if (i - 1) not in starts
		$('.bundle.active').data(variable, starts)

		updateInlineSymbols()


	renderUsers() if 'users' of data
	

Avg = (list) -> Sum(list) / list.length
Sum = (list) -> s = 0; s += item for item in list; s
StDev = (list) -> mu = Avg(list); Math.sqrt Avg((item - mu) * (item - mu) for item in list)


compute_sync_offset = ->
	#here is the rather complicated code to calculate
	#then offsets of the time synchronization stuff
	#it's totally not necessary to do this, but whatever
	#it might make the stuff work better when on an
	#apple iOS device where screen drags pause the
	#recieving of sockets/xhrs meaning that the sync
	#might be artificially inflated, so this could
	#counteract that. since it's all numerical math
	#hopefully it'll be fast even if sync_offsets becomes
	#really really huge

	
	sync_offsets = sync_offsets.slice(-20)

	thresh = Avg sync_offsets
	below = (item for item in sync_offsets when item <= thresh)
	sync_offset = Avg(below)
	# console.log 'frst iter', below
	thresh = Avg below
	below = (item for item in sync_offsets when item <= thresh)
	room.sync_offset = Avg(below)

	# console.log 'sec iter', below
	$('#sync_offset').text(room.sync_offset.toFixed(1) + '/' + StDev(below).toFixed(1) + '/' + StDev(sync_offsets).toFixed(1))

test_latency = ->
	return unless connected()
	initialTime = +new Date
	sock.emit 'echo', {}, (firstServerTime) ->
		recieveTime = +new Date
		
		CSC1 = recieveTime - initialTime
		latency_log.push CSC1
		sync_offsets.push recieveTime - firstServerTime

		sock.emit 'echo', { avg: Avg(latency_log.slice(-10)), std: StDev(latency_log.slice(-10)), n: latency_log.length }, (secondServerTime) ->
			secondTime = +new Date
			CSC2 = secondTime - recieveTime
			SCS1 = secondServerTime - firstServerTime

			sync_offsets.push secondTime - secondServerTime

			latency_log.push SCS1
			latency_log.push CSC2

			compute_sync_offset()

			if latency_log.length > 0
				$('#latency').text(Avg(latency_log).toFixed(1) + "/" + StDev(latency_log).toFixed(1) + " (#{latency_log.length})")


setTimeout ->
	test_latency()
	setInterval -> 
		test_latency()
	, 30 * 1000
, 2000


cache_event = ->
	status = applicationCache.status
	switch applicationCache.status
		when applicationCache.UPDATEREADY
			$('#cachestatus').text 'Updated'
			#applicationCache.swapCache()
			$('#update').slideDown()		
			if localStorage.auto_reload is "yay" or $('#update').data('force') is true
				setTimeout ->
					location.reload()
				, 200 + Math.random() * 1000
			applicationCache.swapCache()
		when applicationCache.UNCACHED
			$('#cachestatus').text 'Uncached'
		when applicationCache.OBSOLETE
			$('#cachestatus').text 'Obsolete'
		when applicationCache.IDLE
			$('#cachestatus').text 'Cached'
		when applicationCache.DOWNLOADING
			$('#cachestatus').text 'Downloading'
		when applicationCache.CHECKING
			$('#cachestatus').text 'Checking'

do -> # isolate variables from globals
	if document.hidden? then hidden = 'hidden'; event = 'visibilitychange'
	else if document.mozHidden? then hidden = 'mozHidden'; event = 'mozvisibilitychange'
	else if document.msHidden? then hidden = 'msHidden'; event = 'msvisibilitychange'
	else if document.webkitHidden? then hidden = 'webkitHidden'; event = 'webkitvisibilitychange'
	
	if hidden
		document.addEventListener event, ->
			me.set_idle document[hidden]
		, false


	# document.addEventListener listener
	if window.applicationCache
		for name in ['cached', 'checking', 'downloading', 'error', 'noupdate', 'obsolete', 'progress', 'updateready']
			applicationCache.addEventListener name, cache_event

