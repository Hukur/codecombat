ModalView = require 'views/core/ModalView'
template = require 'templates/admin/administer-user-modal'
User = require 'models/User'
Prepaid = require 'models/Prepaid'
StripeCoupons = require 'collections/StripeCoupons'
forms = require 'core/forms'
Prepaids = require 'collections/Prepaids'
LevelSessions = require 'collections/LevelSessions'
Classrooms = require 'collections/Classrooms'

module.exports = class AdministerUserModal extends ModalView
  id: 'administer-user-modal'
  template: template

  events:
    'click #save-changes': 'onClickSaveChanges'
    'click #add-seats-btn': 'onClickAddSeatsButton'
    'click #destudent-btn': 'onClickDestudentButton'
    'click #deteacher-btn': 'onClickDeteacherButton'

  initialize: (options, @userHandle) ->
    @user = new User({_id:@userHandle})
    @supermodel.trackRequest @user.fetch({cache: false})
    @coupons = new StripeCoupons()
    @supermodel.trackRequest @coupons.fetch({cache: false})
    @prepaids = new Prepaids()
    @supermodel.trackRequest @prepaids.fetchByCreator(@userHandle)
    @classrooms = new Classrooms()
    @supermodel.trackRequest(@classrooms.fetch({data:{ownerID: @user.id}})).then =>
      @classrooms.each (classroom) =>
        classroom.levelSessions = new LevelSessions()
        @supermodel.trackRequests classroom.levelSessions.fetchForAllClassroomMembers(classroom)
    
  onLoaded: ->
    @allLevelSessions = new LevelSessions(_.reduce((@classrooms.map (c) -> c.levelSessions.models), (a,b) -> (a.concat(b))))
    console.log @allLevelSessions
    mostRecentSession = @allLevelSessions.max (session) ->
      new Date(session.get('changed'))
    console.log new Date(mostRecentSession.get('changed'))
    console.log @allLevelSessions.filter (session) ->
      changed = new Date(session.get('changed'))
      if changed > new Date(mostRecentSession.get('changed'))
        console.log changed
      changed > new Date(mostRecentSession.get('changed'))
    # TODO: Figure out a better way to expose this info, perhaps User methods?
    stripe = @user.get('stripe') or {}
    @free = stripe.free is true
    @freeUntil = _.isString(stripe.free)
    @freeUntilDate = if @freeUntil then stripe.free else new Date().toISOString()[...10]
    @currentCouponID = stripe.couponID
    @none = not (@free or @freeUntil or @coupon)
    super()
    
  onClickSaveChanges: ->
    stripe = _.clone(@user.get('stripe') or {})
    delete stripe.free
    delete stripe.couponID

    selection = @$el.find('input[name="stripe-benefit"]:checked').val()
    dateVal = @$el.find('#free-until-date').val()
    couponVal = @$el.find('#coupon-select').val()
    switch selection
      when 'free' then stripe.free = true
      when 'free-until' then stripe.free = dateVal
      when 'coupon' then stripe.couponID = couponVal

    @user.set('stripe', stripe)
    options = {}
    options.success = => @hide()
    @user.patch(options)

  onClickAddSeatsButton: ->
    attrs = forms.formToObject(@$('#prepaid-form'))
    attrs.maxRedeemers = parseInt(attrs.maxRedeemers)
    return unless _.all(_.values(attrs))
    return unless attrs.maxRedeemers > 0
    return unless attrs.endDate and attrs.startDate and attrs.endDate > attrs.startDate
    attrs.startDate = new Date(attrs.startDate).toISOString()
    attrs.endDate = new Date(attrs.endDate).toISOString()
    _.extend(attrs, {
      type: 'course'
      creator: @user.id
      properties:
        adminAdded: me.id
    })
    prepaid = new Prepaid(attrs)
    prepaid.save()
    @state = 'creating-prepaid'
    @renderSelectors('#prepaid-form')
    @listenTo prepaid, 'sync', ->
      @state = 'made-prepaid'
      @renderSelectors('#prepaid-form')

  onClickDestudentButton: (e) ->
    button = $(e.currentTarget)
    button.attr('disabled', true).text('...')
    Promise.resolve(@user.destudent())
    .then =>
      button.remove()
    .catch (e) =>
      button.attr('disabled', false).text('Destudent')
      noty { 
        text: e.message or e.responseJSON?.message or e.responseText or 'Unknown Error'
        type: 'error'
      }
      if e.stack
        throw e

  onClickDeteacherButton: (e) ->
    button = $(e.currentTarget)
    button.attr('disabled', true).text('...')
    Promise.resolve(@user.deteacher())
    .then =>
      button.remove()
    .catch (e) =>
      button.attr('disabled', false).text('Destudent')
      noty {
        text: e.message or e.responseJSON?.message or e.responseText or 'Unknown Error'
        type: 'error'
      }
      if e.stack
        throw e
