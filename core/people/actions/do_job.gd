class_name DoJob
extends Action
## Take or carry on with work from the jobs board.


func start(people: People, person: Person) -> bool:
	return people.jobs != null and people.jobs.wants_work(person) and people.jobs.carry_on(person)
