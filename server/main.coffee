console.log 'hello from protobowl v3', __dirname, process.cwd()

express = require 'express'
fs = require 'fs'
http = require 'http'
url = require 'url'

passport = require 'passport'
BrowserID = require('passport-browserid').Strategy

parseCookie = require('express/node_modules/cookie').parse
rooms = {}
{QuizRoom} = require '../shared/room'
{QuizPlayer} = require '../shared/player'
{checkAnswer} = require '../shared/checker'

names = require '../shared/names'
uptime_begin = +new Date

app = express()
server = http.createServer(app)

app.set 'views', "server/views" # directory where the jade files are
# app.set 'view options', layout: false
app.set 'trust proxy', true


io = require('socket.io').listen(server)

io.configure 'production', ->
	io.set "log level", 0
	io.set "browser client minification", true
	io.set "browser client gzip", true

io.configure 'development', ->
	io.set "log level", 2
	io.set "browser client minification", true
	io.set "browser client gzip", true



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
		compile_date = new Date;

		compileLess = ->
			console.log 'compiling less'
			lessPath = 'static/less/protobowl.less'
			fs.readFile lessPath, 'utf8', (err, data) ->
				throw err if err

				parser = new(less.Parser)({
					paths: [path.dirname(lessPath)],
					filename: lessPath
				})

				parser.parse data, (err, tree) ->
					css = tree?.toCSS {
						compress: false
					}

					source_list.push {
						code: "/* protobowl_css_build_date: #{compile_date} */\n#{css}",
						err: err,
						file: "static/protobowl.css"
					}
					compileCoffee()


		file_list = ['app', 'offline', 'auth']
		
		compileCoffee = ->
			file = file_list.shift()
			return saveFiles() if !file
			console.log 'compiling coffee', file
			
			snockets.getConcatenation "client/#{file}.coffee", (err, js) ->
				source_list.push {
					code: "protobowl_#{file}_build = '#{compile_date}';\n#{js}", 
					err: err, 
					file: "static/#{file}.js"
				}
				compileCoffee()

		saveFiles = ->
			console.log 'saving files'
			error_message = ''
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
							writeManifest()

		writeManifest = ->
			console.log 'saving manifest'
			fs.readFile 'static/offline.appcache', 'utf8', (err, data) ->
				throw err if err
				data = data.replace(/INSERT_DATE.*?\n/, 'INSERT_DATE '+(new Date).toString() + "\n")
				fs.writeFile 'static/offline.appcache', data, (err) ->
					throw err if err
					io.sockets.emit 'force_application_update', +new Date
					scheduledUpdate = null


		compileLess()
	watcher = (event, filename) ->
		return if filename in ["offline.appcache", "protobowl.css", "app.js"]
		
		unless scheduledUpdate
			console.log "changed file", filename
			scheduledUpdate = setTimeout updateCache, 500

	fs.watch "shared", watcher
	fs.watch "client", watcher
	fs.watch "static/less", watcher
	fs.watch "server/views", watcher


try 
	remote = require './remote'
catch err
	remote = require './local'

if app.settings.env is 'production' and remote.deploy
	log_config = remote.deploy.log
	journal_config = remote.deploy.journal
	console.log 'set to deployment defaults'


mongoose = require('mongoose')
db = mongoose.createConnection 'localhost', 'protobowluser_db'

db.on 'error', (err) ->
	console.log 'Database Error', err

db.on 'open', (err) ->
	console.log 'opened database', err

user_schema = new mongoose.Schema {
	email: String,
	username: String,
	ninja: Boolean,
	events: Array
}

User = db.model 'User', user_schema
users = User.collection
users.ensureIndex { id: 1, email: 1, username: 1, ninja:1, events: 1 }


authenticate_data = (email, callback) ->
	query = User.findOne {"email":email}

	execute_query query, (user) ->
		if user
			callback(user)
		else
			callback(null)

execute_query = (query, callback) ->
	query.exec (err, user) ->
		callback(user)

# Passport Serialize and Deserialize Functions
passport.serializeUser (user, done) ->
	done null, user

passport.deserializeUser (user, done) ->
	done null, user

# Passport-BrowserID Strategy
passport.use 'browserid', new BrowserID {audience: 'localhost:5555'},
	(email, done) ->
		query = User.findOne {"email":email}

		authenticate_data email, (theData) ->
			if theData
				done null, theData
			else
				newUser = new User({'email':email, 'username':'randomusername', 'ninja':0, 'ids': []})
				newUser.save (err) ->
				if err 
					return handleError(err)

				done null, newUser


app.use express.compress()
# app.use express.staticCache()
app.use express.cookieParser()
app.use express.bodyParser()
app.use express.session({ secret: 'keyboard cat' })
app.use express.static('static')
app.use express.favicon('static/img/favicon.ico')
app.use passport.initialize()
app.use passport.session()

crypto = require 'crypto'

# simple helper function that hashes things
sha1 = (text) ->
	hash = crypto.createHash('sha1')
	hash.update(text)
	hash.digest('hex')

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
			log 'next', [@name, question.answer]
			callback(question)
		if @next_id and @show_bonus
			remote.get_by_id @next_id, cb
		else
			category = (if @category is 'custom' then @distribution else @category)
			remote.get_question @type, @difficulty, category, cb

	get_parameters: (type, difficulty, callback) -> remote.get_parameters(type, difficulty, callback)

	count_questions: (type, difficulty, category, cb) -> remote.count_questions(type, difficulty, category, cb) 

	journal: -> journal_queue[@name] = +new Date

	end_buzz: (session) ->
		if @attempt?.user
			ruling = @check_answer @attempt.text, @answer, @question
			log 'buzz', [@name, @attempt.user + '-' + @users[@attempt.user].name, @attempt.text, @answer, ruling]
		super(session)

	deserialize: (data) ->
		blacklist = ['users']
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

	disco: (data) ->
		if data.old_socket and io.sockets.socket(data.old_socket)
			io.sockets.socket(data.old_socket).disconnect()
		if !data.version or data.version < 5
			io.sockets.emit 'force_application_update', +new Date
			io.sockets.emit 'application_update', +new Date
			io.sockets.socket(sock).disconnect() for sock in @sockets
	
	chat: (data) ->
		super(data)
		log 'chat', [@room.name, @id + '-' + @name, data.text] if data.done

	verb: (action, no_rate_limit) -> 
		super(action, no_rate_limit)
		log 'verb', [@room.name, @id + '-' + @name, action]

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

	user_auth: (assertion, cb) ->
		console.log assertion
		cb?()

	add_socket: (sock) ->
		if @sockets.length is 0
			@last_session = @room.serverTime()
			@verb 'joined the room'

		@sockets.push sock.id unless sock.id in @sockets
		blacklist = ['add_socket', 'emit', 'disconnect']
		
		for attr of this when typeof this[attr] is 'function' and attr not in blacklist and attr[0] != '_'
			# wow this is a pretty mesed up line
			do (attr) => sock.on attr, (args...) => this[attr](args...)

		id = sock.id

		@room.journal()
		
		user_count_log 'connected ' + @id + '-' + @name, @room.name

		sock.on 'disconnect', =>
			@sockets = (s for s in @sockets when s isnt id)
			if @sockets.length is 0
				@disconnect()
				@room.journal()
				user_count_log 'disconnected ' + @id + '-' + @name, @room.name


	emit: (name, data) ->
		for sock in @sockets
			io.sockets.socket(sock).emit(name, data)

user_count_log = (message, room_name) ->
	active_count = 0
	online_count = 0
	for name, room of rooms
		for uid, user of room.users
			online_count++ if user.online()
			active_count++ if user.active()
	log 'user_count', { online: online_count, active: active_count, message: message, room: room_name}


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
	config = url.parse(headers.referer)
	
	if config.host isnt 'protobowl.com' and app.settings.env isnt 'development' and config.protocol is 'http:'
		config.host = 'protobowl.com'
		sock.emit 'application_update', +new Date
		sock.emit 'redirect', url.format(config)
		sock.disconnect()
		return

	if config.pathname is '/stalkermode/patriot'
		sock.join 'stalkermode-dash'
		return

	cookie = parseCookie(headers.cookie)
	return sock.disconnect() unless cookie.protocookie and config.pathname
	# set the config stuff
	is_god = /god/.test config.search
	is_ninja = /ninja/.test config.search
	# configger the things which are derived from said parsed stuff
	room_name = config.pathname.replace(/^\/*/g, '').toLowerCase()
	question_type = (if room_name.split('/').length is 2 then room_name.split('/')[0] else 'qb')

	# get the room
	load_room room_name, (room, is_new) ->
		if is_new
			room.type = question_type

		publicID = sha1(cookie.protocookie + room_name)

		publicID = "__secret_ninja_#{Math.random().toFixed(4).slice(2)}" if is_ninja
		publicID += "_god" if is_god
		

		# get the user's identity
		existing_user = (publicID of room.users)
		unless room.users[publicID]
			room.users[publicID] = new SocketQuizPlayer(room, publicID) 
			if room_name in public_room_list
				room.users[publicID].lock = (Math.random() < 0.6) # set defaults on big public rooms to lock

		user = room.users[publicID]
		if room.serverTime() < user.banned
			sock.emit 'redirect', "/#{room_name}-banned"
			sock.disconnect()
			return
		user.name = 'secret ninja' if is_ninja
		
		sock.join room_name
		
		user.add_socket sock
		if is_god
			sock.join name for name of rooms

		sock.emit 'joined', { id: user.id, name: user.name, existing: existing_user }
		
		# tell that there's a new person at the partaay
		room.sync(3)

		# # detect if the server had been recently restarted
		if new Date - uptime_begin < 1000 * 60 and existing_user
			sock.emit 'log', {verb: 'The server has recently been restarted. Your scores may have been preserved in the journal (however, restoration is experimental). This may have been part of a software update, or the result of an unexpected server crash. We apologize for any inconvenience this may have caused.'}
			sock.emit 'application_update', +new Date # check for updates in case it was an update


journal_queue = {}

process_journal_queue = ->
	room_names = Object.keys(journal_queue).sort (a, b) -> journal_queue[a] - journal_queue[b]
	return if room_names.length is 0
	first = room_names[0]
	delete journal_queue[first]
	if first of rooms
		partial_journal first

setInterval process_journal_queue, 1000

last_full_sync = 0
partial_journal = (name) ->
	journal_config.path = '/journal'
	journal_config.method = 'POST'
	req = http.request journal_config, (res) ->
		res.setEncoding 'utf8'
		# console.log "committed journal for", name
		res.on 'data', (chunk) ->
			if chunk == 'do_full_sync'
				if last_full_sync < new Date - 1000 * 60 * 2
					log 'log', 'got trigger to do full sync'
					last_full_sync = +new Date
					journal_queue = {} # full syncs clear queue
					full_journal_sync()
	req.on 'error', (e) ->
		log 'error', 'journal error ' + e.message
		# console.log "journal error"
	req.write(JSON.stringify(rooms[name].serialize()))
	req.end()

full_journal_sync = ->
	backup = (room.serialize() for name, room of rooms)
	journal_config.path = '/full_sync'
	journal_config.method = 'POST'
	req = http.request journal_config, (res) ->
		# console.log "done full sync"
		log 'log', 'completed full sync'
	req.on 'error', (e) ->
		log 'error', 'full sync error ' + e.message
	req.write(JSON.stringify(backup))
	req.end()

rooms = {}

# this is actually really quite hacky

restore_journal = (callback) ->
	journal_config.path = '/retrieve'
	journal_config.method = 'GET'
	req = http.request journal_config, (res) ->
		res.setEncoding 'utf8'
		packet = ''
		res.on 'data', (chunk) ->
			packet += chunk
		res.on 'end', ->
			console.log "Restoring Journal Contents #{packet.length} bytes"
			json = JSON.parse(packet)

			# a new question's gonna be pickt, so just restore settings 
			# fields = ["type", "difficulty", "distribution", "category", "rate", "answer_duration", "max_buzz", "no_skip", "admins"]
			for name, data of json when !(name of rooms)
				room = new SocketQuizRoom(name) 
				rooms[name] = room
				room.deserialize data
			console.log 'restored journal'
			callback() if callback
	req.on 'error', ->
		console.log "Journal not accessible. Starting with defaults."
		callback() if callback
	req.end()


clearInactive = ->
	# garbazhe collectour
	for name, room of rooms
		len = 0
		offline_pool = (username for username, user of room.users when user.sockets.length is 0)
		overcrowded_room = offline_pool.length > 12
		big_room = Object.keys(room.users).length > 12
		
		oldest_user = ''
		if overcrowded_room
			oldest = offline_pool.sort (a, b) -> 
				return room.users[a].last_action - room.users[b].last_action
			oldest_user = oldest[0]

		for username, user of room.users
			len++
			if !user.online() and user.id not in user.room.admins
				evict_user = false
				if overcrowded_room and username is oldest_user
					evict_user = true
				if evict_user or
				(user.last_action < new Date - 1000 * 60 * 15 and user.guesses is 0) or
				(big_room and user.correct < 2 and user.last_action < new Date - 1000 * 60 * 5)
					log 'reap_user', {
						seen: user.seen, 
						guesses: user.guesses, 
						early: user.early, 
						interrupts: user.interrupts, 
						correct: user.correct, 
						time_spent: user.time_spent,
						last_action: user.last_action,
						room: name,
						id: user.id,
						name: user.name
					}
					reaped.users++
					reaped.seen += user.seen
					reaped.guesses += user.guesses
					reaped.early += user.early
					reaped.interrupts += user.interrupts
					reaped.correct += user.correct
					reaped.time_spent += user.time_spent
					reaped.last_action = +new Date
					len--
					delete room.users[username]
					overcrowded_room = false
		if len is 0
			# console.log 'removing empty room', name
			log 'reap_room', name
			delete rooms[name]
			reaped.rooms++



setInterval clearInactive, 1000 * 10 # every ten seconds


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

# think of it like a filesystem swap; slow access external memory that is used to save ram
swapInactive = ->
	for name, room of rooms
		online = (user for username, user of room.users when user.online())
		continue if online.length > 0
		events = (room.serverTime() - user.last_action for username, user of room.users)
		shortest_lapse = Math.min.apply @, events
		continue if shortest_lapse < 1000 * 60 * 20 # things are stale after a few minutes
		# ripe for swapping
		remote.archiveRoom room, (name) ->
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


app.post '/stalkermode/algore', (req, res) ->
	remote.initialize_remote (time, layers) ->
		res.end("counted all cats in #{time}ms: #{util.inspect(layers)}")

app.get '/stalkermode/full', (req, res) ->
	res.render 'admin.jade', {
		env: app.settings.env,
		mem: util.inspect(process.memoryUsage()),
		start: uptime_begin,
		reaped: reaped,
		full_room: true,
		queue: Object.keys(journal_queue).length,
		rooms: rooms
	}

app.get '/stalkermode/users', (req, res) -> res.render 'users.jade', { rooms: rooms }

app.get '/stalkermode/cook', (req, res) ->
	remote.cook(req, res)
	res.redirect '/stalkermode'

app.get '/stalkermode/logout', (req, res) ->
	res.clearCookie 'protoauth'
	res.redirect '/stalkermode'


app.get '/stalkermode/user/:room/:user', (req, res) ->
	u = rooms?[req.params.room]?.users?[req.params.user]
	res.render 'user.jade', { room: req.params.room, id: req.params.user, user: u, text: util.inspect(u)}

app.post '/stalkermode/emit/:room/:user', (req, res) ->
	u = rooms?[req.params.room]?.users?[req.params.user]
	u.emit req.body.action, req.body.text
	res.redirect "/stalkermode/user/#{req.params.room}/#{req.params.user}"

app.post '/stalkermode/exec/:command/:room/:user', (req, res) ->
	rooms?[req.params.room]?.users?[req.params.user]?[req.params.command]?()
	res.redirect "/stalkermode/user/#{req.params.room}/#{req.params.user}"

app.post '/stalkermode/disco/:room/:user', (req, res) ->
	u = rooms?[req.params.room]?.users?[req.params.user]
	io.sockets.socket(sock).disconnect() for sock in u.sockets
	res.redirect "/stalkermode/user/#{req.params.room}/#{req.params.user}"

app.get '/stalkermode', (req, res) ->
	util = require('util')
	res.render 'admin.jade', {
		env: app.settings.env,
		mem: util.inspect(process.memoryUsage()),
		start: uptime_begin,
		reaped: reaped,
		full_room: false,
		queue: Object.keys(journal_queue).length,
		rooms: rooms
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
	remote.Question.findById mongoose.Types.ObjectId(req.params.id), (err, doc) ->
		for key, val of req.body
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

app.get '/stalkermode/:other', (req, res) -> res.redirect '/stalkermode'

app.get '/401', (req, res) -> res.render 'auth.jade', {}

app.post '/401', (req, res) -> remote.authenticate(req, res)

app.get '/new', (req, res) -> res.redirect '/' + names.generatePage()


ensureAuthenticated = (req, res, next) ->
	return next() if req.isAuthenticated()
	res.redirect '/signin'

app.get '/signin', (req, res) -> 
	return res.redirect '/' if req.user
	res.render './info/signin.jade', {user:req.user}

app.get '/user/profile', ensureAuthenticated, (req, res) -> 
	res.render './user/profile.jade', {user:req.user}

app.get '/user/stats', ensureAuthenticated,  (req, res) -> 
	res.render './user/stats.jade', {user:req.user}


app.get '/', (req, res) -> 
	console.log(req.user)
	res.render './info/home.jade', {user:req.user}


app.get '/logout', (req, res) ->
	req.session.destroy()
	res.redirect('/')

app.post '/auth/browserid', passport.authenticate('browserid', { failureRedirect: '/login' }), (req, res) ->
	res.redirect('/');

app.post '/auth/link', (req, res, next) ->
	passport.authenticate('browserid', (err, user, info) ->
		return next(err) if err
		res.end 'fail' if !user
		req.login user, (err) ->
			# TODO: LINK THE ID TO THE DATABASE
			console.log "YO PERSON WHO IS PROBABLY GOING TO BE BEN IF HE EVER SEES THIS: 
			Right here, we have the magical user id which you can link to the session thingy
			because yeah, stuff is stuff. Basically, just take that req.body.id number and
			save it to the database, that is, you add it to the id list.

			I'm guessing that you're probably going to read this from your terminal and
			then you're gonna be all 'wtf man wai so many spaces', and that's just because
			spaces man, are spaces. SPACE.

			So yeah, what u gonna do here? um. Yeah, you can uh just take that req.body.id and then
			save it to the database because i hate databases so i aint knowin how u doings
			dat. 

			I feel oblgiated to write more here because otherwise it wouldn't be noticable
			enough for the casual terminal watcher, but yeah watsevers.

			BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN 
			BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN 
			BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN BEN 

			OKAY. YEAH. WOOOOO
			", req.body.id

			res.end JSON.stringify(user)
	)(req, res, next)





app.get '/:channel', (req, res) ->
	name = req.params.channel
	if name in remote.get_types()
		res.redirect "/#{name}/lobby"
	else
		res.render './game/room.jade', { name, user: null } # USER MUST BE NULL

app.get '/:type/:channel', (req, res) ->
	name = req.params.channel
	res.render './game/room.jade', { name, user: null} # USER MUST BE NULL


remote.initialize_remote()
port = process.env.PORT || 5555
restore_journal ->
	server.listen port, ->
		console.log "listening on port", port