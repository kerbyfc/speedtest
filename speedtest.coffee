class Speedtest

  ###
   # параметры спидтеста
  ###
  options:
    iterations : 10 # сколько файлов выкачивать
    sizes      : [81, 164, 239, 319, 409, 490, 560, 656, 737, 820]
    maxIdle    : 12000 # максимальное время простоя
    ext        : "jpg"

  ###
   # тут храним функции обратного вызова
   # для изменения вью
  ###
  callbacks: {}

  state: null
  error: null

  ###
   # создание спидтеста
   # @param  { Array  } servers хосты с указанием протокола
   # @param  { String } path путь до файлов
   # @return { Object } инстанс
  ###
  constructor: (servers, path = 'speedtest/files') ->
    @servers = if location.host.match(/10\.0\.2\.2|localhost/i)?
      "http://10.40.7.124"
    else
      servers
    @servers = [@servers] if typeof @servers is 'string'
    @options.path = path.replace /(^[\s\/]+)|([\s\/]+$)/g, ''
    @options.totalSize = _.reduce @options.sizes, (acc, s) -> acc + s

  ###
   # summary
   # @param  { String } server хост
   # @param  { Number } iteration номер итерации/файла
   # @return { String } url
  ###
  url: (server, iteration) ->
    [ server, @options.path, iteration ].join('/') +
        "." + @options.ext + "?" + new Date().getTime()

  ###
   # начать тестирование с первого сервера
   # @return {Object} состояние тестирования для текущего сервера (@dimension)
  ###
  start: =>
    unless @state is "busy"
      @state = "busy"
      @error = null
      @trigger 'start'

      @batch = _.reduce @servers, (batch, srv) ->
        batch.push
          err       : null
          host      : srv
          meterings : []
          progress  : 0
          step      : 0
          time      : 0
          received  : 0
        batch
      , []

      @i = -1
      @_startDimension()

    else
      false

  ###
   # остановить тестирование
   # @return {Object} общее состояние тестирования
  ###
  abort: =>
    if @state is "busy"
      @state = "aborted"
      @trigger 'abort', @dimension, @batch
      @_cleanup()
    else
      false

  ###
   # очистка состояния тестирования
   # @return {Object} общее состояние тестирования
  ###
  _cleanup: =>
    clearTimeout @_timer
    @_timer = null
    @batch

  ###
   # начать тест следующего сервера
   # @return {Object} состояние тестирования для текущего сервера (@dimension)
  ###
  _startDimension: =>
    if @state is "busy"
      @i++
      if @dimension = @batch[@i]
        @trigger "dimension:start"
        @dimension.index = @i
        @_doMetering()
      else
        @_finish()

  ###
   # запустить замер/итерацию
   # @param  { Number } i номер итерации/замера/файла
   # @return { Object } состояние тестирования для текущего сервера (@dimension)
  ###
  _doMetering: (i = 0) =>
    if @state is "busy"

      if i is @options.iterations
        return @_finishDimension()

      @_timer = setTimeout =>
        @_onError "timed_out"
      , @options.maxIdle

      img = new Image()
      img.onload  = @_onMeteringFinish
      img.onerror = @_onError

      metering =
        img   : img
        src   : @url @dimension.host, i+1
        size  : @options.sizes[i]
        start : new Date().getTime()
        step  : i
        err   : null

      @dimension.meterings.push metering
      @trigger 'metering:start', metering

      metering.img.src = metering.src
      @dimension

  ###
   # Обработать успешнове выкачивание картинки
   # @return {Object} состояние тестирования для текущего сервера (@dimension)
  ###
  _onMeteringFinish: =>
    if @state is "busy" and @dimension?

      @_cleanup()
      metering = @dimension.meterings[ @dimension.step ]
      metering.time = new Date().getTime() - metering.start

      @dimension.time     += metering.time
      @dimension.received += metering.size
      @dimension.progress = (@dimension.received / @options.totalSize) * 100

      @trigger 'metering:finish', metering, @dimension
      @_doMetering ++@dimension.step

  ###
   # закончить тестирование
   # @return {Object} общее состояние тестирования / состояние
   # тестирования для текущего сервера (@dimension)
  ###
  _finishDimension: =>
    @_calcSpeed @dimension
    @trigger 'dimension:finish', @dimension, @batch
    @_startDimension()

  ###
   # окончание тестирования, расчет скорости
  ###
  _finish: =>
    @state = "success"
    @average =
      time: _.reduce @batch, ((acc, t) -> acc + t.time), 0
      received: _.reduce @batch, ((acc, t) -> acc + t.received), 0
    @_calcSpeed @average
    @trigger 'finish', @batch, @average

  ###
   # расчет скорости
   # @param  { Object } test = dimensionx or metering
   # @return { Object }
  ###
  _calcSpeed: (test) ->
    kbs = test.received / (test.time/1000)
    test.speed =
      bt   : kbs * 1024
      kb   : kbs
      mb   : kbs / 1024
      bit  : kbs*8 * 1024
      kbit : kbs*8
      mbit : kbs*8 / 1024
    test

  ###
   # обработать фейл по таймауту
   # @return {Object} общее состояние тестирования
  ###
  _onFail: =>
    if @state is "busy"

      @state = "failure"
      @error = "timed_out"

      @trigger 'fail', @error, @dimension, @batch
      @_cleanup()

      @_startDimension()

  ###
   # обработать ошибку
   # @param  { Event|String} e событие из img.onerror или текст о причине ошибки
   # @return { Object } общее состояние тестирования
  ###
  _onError: (reason) =>
    if @state is "busy"

      @error = if typeof reason is "string"
        reason
      else
        "failed_to_connect"
      @state = "failure"

      @trigger 'error', @error, @dimension, @batch
      @_cleanup()

  ###
   # добавить обработчкик
   # @param { String   } sign ключ обработчика
   # @param { Function } callback обработчик
  ###
  on: (sign, callback) =>
    @callbacks[sign] = callback

  ###
   # инициировать выполнения обраотчика по ключу
   # @param {String} sign ключ обработчика
  ###
  trigger: (sign, args...) =>
    @callbacks[sign]? args...
