# Presentation Framework

This is a stand-alone presentation framework example.

## Run it locally

```
$ bundle install
$ shotgun
```

Visit http://localhost:9393

## Run it through Habitat

```
$ export HAB_DOCKER_OPTS="-p 8000:9393"
$ hab studio enter
$ build
$ hab sup start ORIGIN/presentation-framework-DATETIME.hart
```

Visit http://localhost:9393

## Run it through Docker

```
$ docker pull burtlo/presentation-framework
$ docker run -p 8000:9393 -it burtlo/presentation-framework
```

Visit http://localhost:9393
