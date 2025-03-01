PYTHON?=python
USE_BUNDLE?=true
VERSION?=$(shell sed -ne "s|^VERSION\s*=\s*'\([^']*\)'.*|\1|p" setup.py)
WITH_CYTHON?=$(shell $(PYTHON)  -c 'import Cython.Build.Dependencies' >/dev/null 2>/dev/null && echo " --with-cython" || true)
PYTHON_BUILD_VERSION?=*

MANYLINUX_IMAGES= \
	manylinux1_x86_64 \
	manylinux1_i686 \
	manylinux_2_24_x86_64 \
	manylinux_2_24_i686 \
	manylinux2014_aarch64 \
	manylinux_2_24_aarch64 \
	manylinux_2_24_ppc64le \
	manylinux_2_24_s390x \
	musllinux_1_1_x86_64 \
	musllinux_1_1_aarch64

.PHONY: all local sdist test clean realclean

all:  local

local:
	${PYTHON} setup.py build_ext --inplace $(WITH_CYTHON)

sdist dist/lupa-$(VERSION).tar.gz:
	${PYTHON} setup.py sdist

test: local
	PYTHONPATH=. $(PYTHON) -m unittest lupa.tests.test

clean:
	rm -fr build lupa/_lupa*.so lupa/lua*.pyx lupa/*.c
	@for dir in third-party/*/; do $(MAKE) -C $${dir} clean; done

realclean: clean
	rm -fr lupa/_lupa.c

wheel:
	$(PYTHON) setup.py bdist_wheel $(WITH_CYTHON)

qemu-user-static:
	docker run --rm --privileged multiarch/qemu-user-static --reset -p yes

wheel_manylinux: $(addprefix wheel_,$(MANYLINUX_IMAGES))
$(addprefix wheel_,$(filter-out %_x86_64, $(filter-out %_i686, $(MANYLINUX_IMAGES)))): qemu-user-static

wheel_%: dist/lupa-$(VERSION).tar.gz
	@echo "Building $(subst wheel_,,$@) wheels for Lupa $(VERSION)"
	mkdir -p wheelhouse_$(subst wheel_,,$@)
	time docker run --rm -t \
		-v $(shell pwd):/io \
		-e CFLAGS="-O3 -g0 -mtune=generic -pipe -fPIC -flto" \
		-e LDFLAGS="$(LDFLAGS) -fPIC -flto" \
		-e LD=gcc-ld \
		-e AR=gcc-ar \
		-e NM=gcc-nm \
		-e RANLIB=gcc-ranlib \
		-e LUPA_USE_BUNDLE=$(USE_BUNDLE) \
		-e WHEELHOUSE=wheelhouse_$(subst wheel_,,$@) \
		quay.io/pypa/$(subst wheel_,,$@) \
		bash -c 'echo "Python versions: $$(ls /opt/python/ | xargs -n 100 echo)" ; \
			for PYBIN in /opt/python/$(PYTHON_BUILD_VERSION)/bin; do \
				$$PYBIN/python -V; \
				{ time $$PYBIN/pip wheel -v -w /io/$$WHEELHOUSE /io/$< & } ; \
			done; wait; \
			for whl in /io/$$WHEELHOUSE/lupa-$(VERSION)-*-linux_*.whl; do auditwheel repair $$whl -w /io/$$WHEELHOUSE; done; \
			for whl in /io/$$WHEELHOUSE/lupa-$(VERSION)-*-m*linux*.whl; do \
				pyver=$${whl#*/lupa-$(VERSION)-}; pyver=$${pyver%%-m*}; \
				echo "Installing in $${pyver}: $${whl}"; \
				/opt/python/$${pyver}/bin/python -m pip install -U $${whl} && /opt/python/$${pyver}/bin/python -c "import lupa" || exit 1; \
				/opt/python/$${pyver}/bin/python -m pip uninstall -y lupa; \
			done; true'
