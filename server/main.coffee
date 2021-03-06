console.log 'hello from protobowl v3', __dirname, process.cwd()

try 
	remote = require './remote'
catch err
	remote = require './local'

remote.initialize_remote()

express = require 'express'
fs = require 'fs'
http = require 'http'
url = require 'url'

parseCookie = require('express/node_modules/cookie').parse
rooms = {}
{QuizRoom} = require '../shared/room'
{QuizPlayer} = require '../shared/player'
{checkAnswer} = require '../shared/checker'

names = require '../shared/names'
uptime_begin = +new Date

app = express()
server = http.createServer(app)

app.set 'views', "server" # directory where the jade files are
app.set 'view options', layout: false
app.set 'trust proxy', true


io = require('socket.io').listen(server)

io.configure 'production', ->
	io.set "log level", 0
	io.set "browser client minification", true
	io.set "browser client gzip", true
	# io.set 'flash policy port', 0 # nodejitsu does like not other ports
	io.set 'transports', ['websocket', 'htmlfile', 'xhr-polling', 'jsonp-polling']
	

io.configure 'development', ->
	io.set "log level", 2
	io.set "browser client minification", false
	io.set "browser client gzip", false
	io.set 'flash policy port', 0
	io.set 'transports', ['websocket', 'flashsocket', 'htmlfile', 'xhr-polling', 'jsonp-polling']
	

journal_config = { host: 'localhost', port: 15865 }
log_config = { host: 'localhost', port: 18228 }


if app.settings.env is 'development'
	less = require 'less'
	
	Snockets = require 'snockets'
	CoffeeScript = require 'coffee-script'
	Snockets.compilers.coffee = 
		match: /\.js$/
		compileSync: (sourcePath, source) ->
			CoffeeScript.compile source, {filename: sourcePath, bare: true}

	snockets = new Snockets()


	scheduledUpdate = null
	path = require 'path'

	updateCache = ->
		source_list = []
		compile_date = new Date
		timehash = ''
		cache_text = ''

		compileLess = ->
			lessPath = 'client/less/protobowl.less'
			fs.readFile lessPath, 'utf8', (err, data) ->
				throw err if err

				parser = new(less.Parser)({
					paths: [path.dirname(lessPath)],
					filename: lessPath
				})

				parser.parse data, (err, tree) ->
					css = tree?.toCSS {
						compress: true
					}

					source_list.push {
						hash: sha1(css + ''),
						code: "/* protobowl_css_build_date: #{compile_date} */\n#{css}",
						err: err,
						file: "static/protobowl.css"
					}
					compileCoffee()


		file_list = ['app', 'offline', 'auth']
		
		compileCoffee = ->
			file = file_list.shift()
			return saveFiles() if !file
			
			snockets.getConcatenation "client/#{file}.coffee", minify: true, (err, js) ->
				source_list.push {
					hash: sha1(js + ''),
					code: "protobowl_#{file}_build = '#{compile_date}';\n#{js}", 
					err: err, 
					file: "static/#{file}.js"
				}
				compileCoffee()

		saveFiles = ->
			# its something like a unitard
			unihash = sha1((i.hash for i in source_list).join(''))
			if unihash is timehash
				console.log 'files not modified; aborting'
				return
			error_message = ''
				
			console.log 'saving files'
			for i in source_list
				error_message += "File: #{i.file}\n#{i.err}\n\n" if i.err
			if error_message
				io.sockets.emit 'debug', error_message
				console.log error_message
				scheduledUpdate = null
			else
				saved_count = 0
				for i in source_list
					fs.writeFile i.file, i.code, 'utf8', ->
						saved_count++
						if saved_count is source_list.length
							writeManifest(unihash)

		writeManifest = (hash) ->
			data = cache_text.replace(/INSERT_DATE.*?\n/, 'INSERT_DATE '+(new Date).toString() + " # #{hash}\n")
			fs.writeFile 'static/offline.appcache', data, (err) ->
				throw err if err
				io.sockets.emit 'force_application_update', +new Date
				scheduledUpdate = null

		fs.readFile 'static/offline.appcache', 'utf8', (err, data) ->
			cache_text = data
			timehash = cache_text.match(/INSERT_DATE (.*?)\n/)?[1]?.split(" # ")?[1]
			compileLess()
			

	watcher = (event, filename) ->
		return if filename in ["offline.appcache", "protobowl.css", "app.js"]
			
		unless scheduledUpdate
			console.log "changed file", filename
			scheduledUpdate = setTimeout updateCache, 500

	updateCache()
	
	fs.watch "shared", watcher
	fs.watch "client", watcher
	fs.watch "client/less", watcher
	fs.watch "client/lib", watcher
	fs.watch "server/room.jade", watcher


if app.settings.env is 'production' and remote.deploy
	log_config = remote.deploy.log
	journal_config = remote.deploy.journal
	console.log 'set to deployment defaults'


app.use express.compress()
# app.use express.staticCache()
app.use express.static('static')
app.use express.cookieParser()
app.use express.bodyParser()
app.use express.favicon('static/img/favicon.ico')

crypto = require 'crypto'

# simple helper function that hashes things
sha1 = (text) ->
	hash = crypto.createHash('sha1')
	hash.update(text)
	hash.digest('hex')

# basic statistical methods for statistical purposes
Med = (list) -> m = list.sort((a, b) -> a - b); m[Math.floor(m.length/2)] || 0
Avg = (list) -> Sum(list) / list.length
Sum = (list) -> s = 0; s += item for item in list; s
StDev = (list) -> mu = Avg(list); Math.sqrt Avg((item - mu) * (item - mu) for item in list)

# inject the cookies into the session... yo
app.use (req, res, next) ->
	unless req.cookies['protocookie']
		seed = "proto" + Math.random() + "bowl" + Math.random() + "client" + req.headers['user-agent']
		expire_date = new Date()
		expire_date.setFullYear expire_date.getFullYear() + 2

		res.cookie 'protocookie', sha1(seed), {
			expires: expire_date,
			httpOnly: false,
			signed: false,
			secure: false,
			path: '/'
		}

	next()

app.use (req, res, next) ->
	if req.headers.host isnt "protobowl.com" and app.settings.env isnt 'development' and req.protocol is 'http'
		options = url.parse(req.url)
		options.host = 'protobowl.com'
		res.writeHead 301, {Location: url.format(options)}
		res.end()
	else
		if remote.authorized and (/stalkermode/.test(req.path) or 'ninja' of req.query)
			remote.authorized req, (allow) ->
				if allow
					next()
				else
					res.redirect "/401"
		else
			next()

	

log = (action, obj) ->
	req = http.request log_config, ->
		# console.log "saved log"
	req.on 'error', ->
		console.log "backup log", action, JSON.stringify(obj)
	req.write((+new Date) + ' ' + action + ' ' + JSON.stringify(obj) + '\n')
	req.end()

	io.sockets.in("stalkermode-dash").emit action, obj

log 'server_restart', {}

public_room_list = ['hsquizbowl', 'lobby']

class SocketQuizRoom extends QuizRoom
	emit: (name, data) ->
		io.sockets.in(@name).emit name, data

	check_answer: (attempt, answer, question) -> checkAnswer(attempt, answer, question) 

	get_question: (callback) ->
		cb = (question) =>
			log 'next', [@name, question?.answer]
			callback(question)
		if @next_id and @show_bonus
			remote.get_by_id @next_id, cb
		else
			category = (if @category is 'custom' then @distribution else @category)
			remote.get_question @type, @difficulty, category, cb

	get_parameters: (type, difficulty, callback) -> remote.get_parameters(type, difficulty, callback)

	count_questions: (type, difficulty, category, cb) -> remote.count_questions(type, difficulty, category, cb) 

	journal: -> 
		unless @name of journal_queue
			journal_queue[@name] = +new Date

	end_buzz: (session) ->
		if @attempt?.user
			ruling = @check_answer @attempt.text, @answer, @question
			log 'buzz', [@name, @attempt.user + '-' + @users[@attempt.user]?.name, @attempt.text, @answer, ruling]
		super(session)

	merge_user: (id, new_id) ->
		return false if !@users[id]
		if @users[new_id]
			# merge current user into this one
			sum_terms = ['guesses', 'interrupts', 'early', 'seen', 'correct', 'time_spent']
			for term in sum_terms
				@users[new_id][term] += @users[id][term]
			delete @users[id]
		else
			# rename the current user into this new one
			@users[new_id] = @users[id]
			@users[new_id].id = new_id
			delete @users[id]
			
		@emit 'rename_user', {old_id: id, new_id: new_id}
		@sync(1)
		

	deserialize: (data) ->
		blacklist = ['users', 'attempt', 'generating_question']
		for attr, val of data when attr not in blacklist
			@[attr] = val
		for user in data.users
			u = new SocketQuizPlayer(@, user.id)
			@users[user.id] = u
			u.deserialize(user)

class SocketQuizPlayer extends QuizPlayer
	constructor: (room, id) ->
		super(room, id)
		@sockets = []
		@name = names.generateName()
	
	chat: (data) ->
		super(data)
		log 'chat', [@room.name, @id + '-' + @name, data.text] if data.done

	verb: (action, no_rate_limit) -> 
		super(action, no_rate_limit)
		log 'verb', [@room.name, @id + '-' + @name, action]
		@room.journal()

	online: -> @sockets.length > 0

	report_question: (data) ->
		return unless data
		data.room = @room.name
		data.user = @id + '-' + @name
		remote.handle_report data if remote.handle_report
		log 'report_question', data

	report_answer: (data) ->
		return unless data
		data.room = @room.name
		data.user = @id + '-' + @name
		log 'report_answer', data
		

	check_public: (_, fn) ->
		output = {}
		for check_name in public_room_list
			output[check_name] = 0
			if rooms[check_name]?.users
				for uid, udat of rooms[check_name].users
					output[check_name]++ if udat.active()
		fn output if fn

	ban: (duration = 1000 * 60 * 10) ->
		if @room.serverTime() > @banned
			@banned = @room.serverTime() + duration
			@room._ip_ban = {} if !@room._ip_ban
			for ip in @ip()
				@room._ip_ban[ip] = { strikes: 0, banished: 0 } if !@room._ip_ban[ip]
				@room._ip_ban[ip].strikes++

		order = ['b', 'hm', 'cgl', 'mlp']

		destination = order[(order.indexOf(@room.name) + 1)]

		if !destination # nothing, there is nothing
			@banned = 0
			return 

		@emit 'redirect', '/' + destination
		
		for sock in @sockets
			io.sockets.socket(sock)?.disconnect()

	ip_ban: (duration = 1000 * 60 * 15) ->
		@room._ip_ban = {} if !@room._ip_ban
		for ip in @ip()
			@room._ip_ban[ip] = { strikes: 0, banished: @room.serverTime() + duration }
		@ban(duration)

	ip: ->
		ips = []
		for sock_id in @sockets
			sock = io.sockets.socket(sock_id)
			real_ip = sock.handshake?.address?.address
			forward_ip = sock.handshake?.headers?["x-forwarded-for"]
			addr = (forward_ip || real_ip)
			ips.push addr if sock and addr
		return ips


	add_socket: (sock) ->
		if @sockets.length is 0
			@last_session = @room.serverTime()
			@verb 'joined the room'

		@sockets.push sock.id unless sock.id in @sockets
		blacklist = ['add_socket', 'emit', 'disconnect']
		
		sock.on 'disconnect', =>
			@sockets = (s for s in @sockets when (s isnt sock.id and io.sockets.socket(s)))
			if @sockets.length is 0
				@disconnect()
				@room.journal()
				user_count_log 'disconnected ' + @id + '-' + @name, @room.name
		
		for attr of this when typeof this[attr] is 'function' and attr not in blacklist and attr[0] != '_'
			# wow this is a pretty mesed up line
			do (attr) => 
				sock.on attr, (args...) => 
					if @banned and @room.serverTime() < @banned
						@ban()
					else if @__rate_limited and @room.serverTime() < @__rate_limited
						@throttle()
					else
						try
							this[attr](args...)
						catch err
							console.error "Error while running QuizPlayer::#{attr} for #{@room.name}/#{@id} with args: ", args
							console.error err.stack
							@room.emit 'debug', "Error while running QuizPlayer::#{attr} for #{@room.name}/#{@id}.\nPlease email info@protobowl.com with the contents of this error.\n\n#{err.stack}"

		if @banned and @room.serverTime() < @banned
			@ban()
			sock.disconnect()

		@room.journal()
		
		for ip in @ip()
			if @room._ip_ban and @room._ip_ban[ip]
				if @room._ip_ban[ip].strikes >= 3
					@ip_ban()

				if @room.serverTime() < @room._ip_ban[ip].banished
					@ban()
					break


		user_count_log 'connected ' + @id + '-' + @name + " (#{ip})", @room.name



	emit: (name, data) ->
		for sock in @sockets
			io.sockets.socket(sock).emit(name, data)

user_count_log = (message, room_name) ->
	active_count = 0
	online_count = 0
	latencies = []
	for name, room of rooms
		for uid, user of room.users
			if user.online()
				online_count++ 
				active_count++ if user.active()
				latencies.push(user._latency[0]) if user._latency

	log 'user_count', { online: online_count, active: active_count, message: message, room: room_name, avg_latency: Med(latencies), std_latency: StDev(latencies)}


load_room = (name, callback) ->
	if rooms[name] # its really nice and simple if you have it cached
		return callback rooms[name], false
	room = new SocketQuizRoom(name) 
	rooms[name] = room
	if remote.loadRoom
		remote.loadRoom name, (data) ->		
			if data and data.users
				room.deserialize data
				callback room, false
			else
				callback room, true
	else
		callback room, true


io.sockets.on 'connection', (sock) ->
	headers = sock.handshake.headers
	return sock.disconnect() unless headers.referer and headers.cookie
	config = url.parse(headers.referer, true)
	
	is_ninja = 'ninja' of config.query	

	if config.host isnt 'protobowl.com' and app.settings.env isnt 'development' and config.protocol is 'http:'
		config.host = 'protobowl.com'
		sock.emit 'application_update', +new Date
		sock.emit 'redirect', url.format(config)
		sock.disconnect()
		return

	if config.pathname is '/stalkermode/patriot'
		sock.join 'stalkermode-dash'
		return

	# # configger the things which are derived from said parsed stuff

	# if is_ninja and config.pathname is '/scalar.html'
	# 	room_name = "room-#{Math.floor(Math.random() * 42)}"
	# 	publicID = ("#{Math.floor(Math.random() * 20)}0000000000000000000000000000000000000000").slice(0, 40)
	# 	is_ninja = false

	sock.on 'disco', (data) ->
		sock.emit 'force_application_update', Date.now()
		sock.disconnect()

	sock.on 'join', ({cookie, room_name, question_type, old_socket, version}) ->
		if !version or version < 6
			sock.emit 'force_application_update', Date.now()
			sock.disconnect()
		io.sockets.socket(old_socket)?.disconnect() if old_socket
		publicID = sha1(cookie + room_name)
		# get the room
		load_room room_name, (room, is_new) ->
			room.type = question_type if is_new

			if is_ninja
				publicID = "__secret_ninja_#{Math.random().toFixed(4).slice(2)}" 
				if 'id' of config.query
					publicID = (config.query.id + "0000000000000000000000000000000000000000").slice(0, 40)
					is_ninja = false

			# get the user's identity
			existing_user = (publicID of room.users)
			unless room.users[publicID]
				room.users[publicID] = new SocketQuizPlayer(room, publicID) 
				user = room.users[publicID]

				if room_name in public_room_list
					# public rooms default to locked, like cars in the city
					user.lock = true
				else
					if room.active_count() <= 1
						# small room, hey wai not right?
						user.lock = true
					else if room.locked()
						user.lock = true
					else
						# probablistic systems work for lots of things
						user.lock = (Math.random() > 0.5)

			user = room.users[publicID]
			user.name = 'secret ninja' if is_ninja
			sock.join room_name
			user.add_socket sock
			sock.emit 'joined', { id: user.id, name: user.name, existing: existing_user }
			room.sync(3) # tell errybody that there's a new person at the partaay

			# # detect if the server had been recently restarted
			if new Date - uptime_begin < 1000 * 60 and existing_user
				sock.emit 'log', {verb: 'The server has recently been restarted. Your scores may have been preserved in the journal (however, restoration is experimental). This may have been part of a software update, or the result of an unexpected server crash. We apologize for any inconvenience this may have caused.'}
				sock.emit 'application_update', +new Date # check for updates in case it was an update

refresh_stale = ->
	STALE_TIME = 1000 * 60 * 2 # four minutes?
	for name, room of rooms
		continue if !room
		if !room.archived or Date.now() - room.archived > STALE_TIME
			# the room hasn't been archived in a few minutes
			remote.archiveRoom? room
			delete journal_queue[name]
			

setInterval refresh_stale, 1000 * 10 # check 3x every minute

journal_queue = {}

process_queue = ->
	return unless gammasave
	[min_time, min_room] = [Date.now(), null]
	for name, time of journal_queue
		if !rooms[name]
			delete journal_queue[name]
			continue			
		[min_time, min_room] = [time, name] if time < min_time
	return unless min_room
	room = rooms[min_room]
	if !room?.archived or Date.now() - room?.archived > 1000 * 10
		remote.archiveRoom? room
		delete journal_queue[min_room]

setInterval process_queue, 1000	


reaped = {
	name: "__reaped",
	users: 0,
	rooms: 0,
	seen: 0,
	correct: 0,
	guesses: 0,
	interrupts: 0,
	time_spent: 0,
	early: 0,
	last_action: +new Date
}

clearInactive = ->
	# the maximum size a room can be
	MAX_SIZE = 15

	rank_user = (u) -> if u.correct > 2 then u.last_action else u.time_spent
	reap_room = (name) ->
		log 'reap_room', name
		delete rooms[name]
		remote.removeRoom?(name)
		reaped.rooms++
	reap_user = (u) ->
		log 'reap_user', {
			seen: u.seen, 
			guesses: u.guesses, 
			early: u.early, 
			interrupts: u.interrupts, 
			correct: u.correct, 
			time_spent: u.time_spent,
			last_action: u.last_action,
			room: u.room.name,
			id: u.id,
			name: u.name
		}
		reaped.users++
		reaped.seen += u.seen
		reaped.guesses += u.guesses
		reaped.early += u.early
		reaped.interrupts += u.interrupts
		reaped.correct += u.correct
		reaped.time_spent += u.time_spent
		reaped.last_action = +new Date
		delete u.room.users[u.id]

	for room_name, room of rooms
		user_pool = (user for id, user of room.users)
		if user_pool.length is 0
			reap_room room_name
			continue

		offline_pool = (user for user in user_pool when !user.online())
		
		for user in offline_pool when user.correct < 2 and user.last_action < Date.now() - 1000 * 60 * 5
			reap_user user
			continue

		offline_pool.sort (a, b) -> rank_user(a) - rank_user(b)
		if offline_pool.length > 0 and user_pool.length > MAX_SIZE
			reap_user offline_pool[0]
			continue # no point here but it makes the code more poetic


setInterval clearInactive, 1000 * 10 # every ten seconds



# think of it like a filesystem swap; slow access external memory that is used to save ram
swapInactive = ->
	for name, room of rooms
		online = (user for username, user of room.users when user.online())
		continue if online.length > 0
		events = (room.serverTime() - user.last_action for username, user of room.users)
		shortest_lapse = Math.min.apply @, events
		continue if shortest_lapse < 1000 * 60 * 20 # things are stale after a few minutes
		# ripe for swapping
		remote.archiveRoom? room, (name) ->
			delete rooms[name]

if remote.archiveRoom
	# do it every ten seconds like a bonobo
	setInterval swapInactive, 1000 * 10 


util = require('util')

app.post '/stalkermode/kickoffline', (req, res) ->
	clearInactive 1000 * 5 # five seconds
	res.redirect '/stalkermode'

app.post '/stalkermode/announce', (req, res) ->
	io.sockets.emit 'chat', {
		text: req.body.message, 
		session: Math.random().toString(36).slice(3), 
		user: '__' + req.body.name, 
		done: true,
		time: +new Date
	}
	res.redirect '/stalkermode'

# i forgot why it was called al gore; possibly change
app.post '/stalkermode/algore', (req, res) ->
	remote.populate_cache (layers) ->
		res.end("counted all cats #{JSON.stringify(layers, null, '  ')}")

app.get '/stalkermode/users', (req, res) -> res.render 'users.jade', { rooms: rooms }


app.get '/stalkermode/cook', (req, res) ->
	remote.cook(req, res)
	res.redirect '/stalkermode'

app.get '/stalkermode/logout', (req, res) ->
	res.clearCookie 'protoauth'
	res.redirect '/stalkermode'


app.get '/stalkermode/user/:room/:user', (req, res) ->
	u = rooms?[req.params.room]?.users?[req.params.user]
	u2 = {}
	u2[k] = v for k, v of u when k not in ['room'] and typeof v isnt 'function'
		
	res.render 'user.jade', { room: req.params.room, id: req.params.user, user: u, text: util.inspect(u2), ips: u?.ip() }


app.get '/stalkermode/room/:room', (req, res) ->
	u = rooms?[req.params.room]
	u2 = {}
	u2[k] = v for k, v of u when k not in ['users', 'timing', 'cumulative'] and typeof v isnt 'function'
	res.render 'control.jade', { room: u, name: req.params.room, text: util.inspect(u2)}

app.post '/stalkermode/stahp', (req, res) -> process.exit(0)

app.post '/stalkermode/clear_bans/:room', (req, res) ->
	delete rooms?[req.params.room]?._ip_bans
	res.redirect "/stalkermode/room/#{req.params.room}"

app.post '/stalkermode/delete_room/:room', (req, res) ->
	if rooms?[req.params.room]?.users
		for id, u of rooms[req.params.room].users
			for sock in u.sockets
				io.sockets.socket(sock).disconnect()
	rooms[req.params.room] = new SocketQuizRoom(req.params.room)
	res.redirect "/stalkermode/room/#{req.params.room}"


app.post '/stalkermode/disco_room/:room', (req, res) ->
	if rooms?[req.params.room]?.users
		for id, u of rooms[req.params.room].users
			for sock in u.sockets
				io.sockets.socket(sock).disconnect()
	res.redirect "/stalkermode/room/#{req.params.room}"


app.post '/stalkermode/emit/:room/:user', (req, res) ->
	u = rooms?[req.params.room]?.users?[req.params.user]
	u.emit req.body.action, req.body.text
	res.redirect "/stalkermode/user/#{req.params.room}/#{req.params.user}"

app.post '/stalkermode/exec/:command/:room/:user', (req, res) ->
	rooms?[req.params.room]?.users?[req.params.user]?[req.params.command]?()
	res.redirect "/stalkermode/user/#{req.params.room}/#{req.params.user}"

app.post '/stalkermode/unban/:room/:user', (req, res) ->
	rooms?[req.params.room]?.users?[req.params.user]?.banned = 0
	res.redirect "/stalkermode/user/#{req.params.room}/#{req.params.user}"


app.post '/stalkermode/negify/:room/:user/:num', (req, res) ->
	rooms?[req.params.room]?.users?[req.params.user]?.interrupts += (parseInt(req.params.num) || 1)
	rooms?[req.params.room]?.sync(1)
	res.redirect "/stalkermode/user/#{req.params.room}/#{req.params.user}"

app.post '/stalkermode/disco/:room/:user', (req, res) ->
	u = rooms?[req.params.room]?.users?[req.params.user]
	io.sockets.socket(sock).disconnect() for sock in u.sockets
	res.redirect "/stalkermode/user/#{req.params.room}/#{req.params.user}"

gammasave = false

app.get '/stalkermode/gamma-off', (req, res) ->
	gammasave = false
	res.redirect '/stalkermode'

app.get '/stalkermode/hulk-smash', (req, res) ->
	gammasave = Date.now()
	res.redirect '/stalkermode'


app.get '/stalkermode', (req, res) ->
	util = require('util')
	os = require 'os'
	latencies = []
	for name, room of rooms
		latencies.push(user._latency[0]) for id, user of room.users when user._latency and user.online()
	os_info = {
		hostname: os.hostname(),
		type: os.type(),
		platform: os.platform(),
		arch: os.arch(),
		release: os.release(),
		loadavg: os.loadavg(),
		uptime: os.uptime(),
		totalmem: os.totalmem(),
		freemem: os.freemem()
	}
	res.render 'admin.jade', {
		env: app.settings.env,
		mem: util.inspect(process.memoryUsage()),
		start: uptime_begin,
		reaped,
		gammasave,
		avg_latency: Med(latencies),
		std_latency: StDev(latencies),
		cookie: req.protocookie,
		queue: Object.keys(journal_queue).length,
		os: os_info,
		os_text: util.inspect(os_info),
		rooms
	}

app.post '/stalkermode/reports/remove_report/:id', (req, res) ->
	mongoose = require 'mongoose'
	remote.Report.remove {_id: mongoose.Types.ObjectId(req.params.id)}, (err, docs) ->
		res.end 'REMOVED IT' + req.params.id


app.post '/stalkermode/reports/remove_question/:id', (req, res) ->
	mongoose = require 'mongoose'
	remote.Question.remove {_id: mongoose.Types.ObjectId(req.params.id)}, (err, docs) ->
		res.end 'REMOVED IT' + req.params.id


app.post '/stalkermode/reports/change_question/:id', (req, res) ->
	mongoose = require 'mongoose'
	blacklist = ['inc_random', 'seen']
	remote.Question.findById mongoose.Types.ObjectId(req.params.id), (err, doc) ->
		for key, val of req.body when key not in blacklist
			doc[key] = val
		doc.save()
		res.end('gots it')

app.get '/stalkermode/reports/all', (req, res) ->
	remote.Report.find {}, (err, docs) ->
		res.render 'reports.jade', { reports: docs, categories: remote.get_categories('qb') }

app.get '/stalkermode/reports/:type', (req, res) ->
	remote.Report.find {describe: req.params.type}, (err, docs) ->
		res.render 'reports.jade', { reports: docs, categories: remote.get_categories('qb') }

app.get '/stalkermode/patriot', (req, res) -> res.render 'dash.jade'

app.get '/stalkermode/archived', (req, res) -> 
	remote.listArchived (list) ->
		res.render 'archived.jade', { list, rooms }

app.get '/stalkermode/:other', (req, res) -> res.redirect '/stalkermode'

app.get '/401', (req, res) -> res.render 'auth.jade', {}

app.post '/401', (req, res) -> remote.authenticate(req, res)

app.get '/new', (req, res) -> res.redirect '/' + names.generatePage()

app.get '/', (req, res) -> res.redirect '/lobby'

app.get '/:channel', (req, res) ->
	name = req.params.channel
	if name in remote.get_types()
		res.redirect "/#{name}/lobby"
	else
		res.render 'room.jade', { name }

app.get '/:type/:channel', (req, res) ->
	name = req.params.channel
	res.render 'room.jade', { name }

port = process.env.PORT || 5555
server.listen port, ->
	console.log "listening on port", port