define [
  'underscore'
  'moment'
  './danceclass'
], (_, moment, DanceClass) -> 

  describe 'DanceClass model tests', ->
    
    it 'should new dance class be created with default values', ->
      # when creating a dancer withou values
      tested = new DanceClass()
      # then an id was set
      expect(tested).to.have.property 'id'
      expect(tested.id).to.be.a 'string'
      expect(tested.id).to.have.lengthOf 12
      # then all plain attributes have been set to default
      expect(tested).to.have.property 'start', 'Mon 08:00'
      expect(tested).to.have.property 'end', 'Mon 09:00'
      expect(tested).to.have.property 'teatcher', null
      expect(tested).to.have.property 'hall', null
      expect(tested).to.have.property 'year', 2013
      expect(tested).to.have.property 'level', ''
      expect(tested).to.have.property 'kind', ''

    it 'should dance class save raw values', ->
      # given a raw dance class
      raw = 
        id: 'anId'
        kind: 'salsa'
        year: 2014
        level: '2'
        start: 'Wed 18:15'
        end: 'Wed 19:15'
        teatcher: 'Anthony'
        hall: 'Gratte-ciel 1'

      # when creating a dance class with a clone to avoid modifications
      tested = new DanceClass _.clone raw
      # then all defined attributes have been saved
      expect(tested).to.have.property 'id', raw.id
      expect(tested).to.have.property 'kind', raw.kind
      expect(tested).to.have.property 'year', raw.year
      expect(tested).to.have.property 'level', raw.level
      expect(tested).to.have.property 'start', raw.start
      expect(tested).to.have.property 'end', raw.end
      expect(tested).to.have.property 'teatcher', raw.teatcher
      expect(tested).to.have.property 'hall', raw.hall
      expect(tested.toJSON()).to.deep.equal raw

    it 'should dance class not save unallowed values', ->
      # when creating a dance class with unallowed attributes
      tested = new DanceClass unallowed: 'toto'
      # then the attribute was not reported and the dance class created
      expect(tested).not.to.have.property 'unallowed'
