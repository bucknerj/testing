// Resource limits — morrison has 16 cores; reserve 4 for desktop use
def MAX_BUILD_CONCURRENT = 2   // concurrent ninja builds
def BUILD_THREADS = 6          // -j per build (2 × 6 = 12 cores)
def MAX_TEST_CONCURRENT = 4    // concurrent test runs

// Run a map of closures in batches of the given size
def runInBatches(Map jobs, int batchSize) {
    def jobList = jobs.collect { k, v -> [k, v] }
    for (int i = 0; i < jobList.size(); i += batchSize) {
        def batch = [:]
        def end = Math.min(i + batchSize, jobList.size())
        for (int j = i; j < end; j++) {
            batch[jobList[j][0]] = jobList[j][1]
        }
        parallel batch
    }
}

def ENV_SETUP = '''
    eval "$(/home/bucknerj/.local/bin/micromamba shell hook --shell zsh)"
    micromamba activate workshop
    export FFTW_HOME=$CONDA_PREFIX
'''

// SCC-DFTB parameter setup, run in the test CWD just before test.com.
// This is charmm-test's test_script() block for the sccdftb config,
// transcribed: keeping the two hosts identical here is the whole point,
// since anything that differs shows up as a difference in the grade.
//
// The testcases read SCCDFTB_DATA with `genv' and build a path to a
// per-element sccdftb_<ELEMENTS>.dat. `genv' on an unset variable is a
// level-0 warning, which terminates at the default BOMLEV, so without
// the export they stop two lines in with nothing about parameters in
// the message. The .dat files name their .skf files by absolute path,
// so they are generated per host rather than checked in — see
// sccdftb/README.md in the testing repo. Older testcases still want
// ./sccdftb.dat in the CWD, which is what the symlink is for.
def SCCDFTB_DATA_DIR = '/home/bucknerj/src/jenkins/sccdftb_data'
def SCCDFTB_SETUP = """
    export SCCDFTB_DATA=${SCCDFTB_DATA_DIR}
    if [[ -d "\$SCCDFTB_DATA/skf" ]]; then
        python3 \${WORKSPACE}/testing/sccdftb/gen_sccdftb_dat.py \\
            "\$SCCDFTB_DATA/skf" "\$SCCDFTB_DATA" || \\
            echo "WARNING: could not build sccdftb .dat files"
    else
        echo "WARNING: no \$SCCDFTB_DATA/skf; sccdftb tests will skip"
    fi
    if [[ ! -e ./sccdftb.dat && -f "\$SCCDFTB_DATA/sccdftb.dat" ]]; then
        ln -s "\$SCCDFTB_DATA/sccdftb.dat" sccdftb.dat || true
    fi
"""

// Shell snippet to rotate test output: saves current output as old/
def TEST_ROTATE = '''
    if [[ -d output ]]; then
        rm -rf old
        mkdir old
        cp -r output* old/
        rm -rf output*
    fi
    if [[ -d old ]]; then
        for f in test.log compare.log diff.log test_results.xml; do
            if [[ -f $f ]]; then cp $f old/; rm $f; fi
        done
    fi
'''

pipeline {
    agent any
    options {
        timeout(time: 6, unit: 'HOURS')
        timestamps()
    }
    stages {
        stage('Checkout') {
            steps {
                git branch: 'master', url: 'gitlab:/bucknerj/dev-release'
            }
        }
        stage('Checkout Testing') {
            steps {
                dir('testing') {
                    git branch: 'main',
                        url: 'git@github-bucknerj:bucknerj/testing.git'
                }
            }
        }
        stage('Load Configs') {
            steps {
                script {
                    def json = sh(script: """
                        ${ENV_SETUP}
                        python \${WORKSPACE}/testing/charmm-test list --json
                    """, returnStdout: true).trim()
                    def parsed = new groovy.json.JsonSlurper().parseText(json)
                    // Convert LazyMap to HashMap for Jenkins CPS serialization
                    charmmConfigs = new HashMap(parsed)
                    charmmConfigs.each { k, v -> charmmConfigs[k] = new HashMap(v) }
                    echo "Loaded ${charmmConfigs.size()} configurations: ${charmmConfigs.keySet().sort().join(', ')}"
                }
            }
        }
        stage("Configure") {
            steps {
                script {
                    def parallelJobs = [:]
                    charmmConfigs.each { name, cfg ->
                        parallelJobs["Configure ${name}"] = {
                            stage("Configure ${name}") {
                                echo "Configuring ${name}..."
                                sh """
                                    ${ENV_SETUP}
                                    if [[ ! -d install-${name} ]]; then
                                        tool/NewCharmmTree install-${name}
                                    fi
                                    pushd install-${name}
                                    rm -rf build/cmake
                                    ./configure --with-ninja ${cfg.configure}
                                    popd
                                """
                                echo "...finished configuring ${name}"
                            }
                        }
                    }
                    parallel parallelJobs
                }
            }
        }
        stage("Build") {
            steps {
                script {
                    def buildJobs = [:]
                    charmmConfigs.each { name, cfg ->
                        buildJobs["Build ${name}"] = {
                            stage("Build ${name}") {
                                echo "Building ${name}..."
                                sh """
                                    ${ENV_SETUP}
                                    pushd install-${name}
                                    nice -n 10 ninja -j ${BUILD_THREADS} -C build/cmake install
                                    popd
                                """
                                echo "...finished building ${name}"
                            }
                        }
                    }
                    runInBatches(buildJobs, MAX_BUILD_CONCURRENT)
                }
            }
        }
        stage("Test") {
            steps {
                script {
                    // GPU tests — run sequentially to avoid GPU memory contention
                    charmmConfigs.findAll { name, cfg ->
                        cfg.test != false && cfg.gpus
                    }.each { name, cfg ->
                        stage("Test ${name} (GPU)") {
                            echo "Testing ${name} (GPU)..."
                            sh """
                                ${ENV_SETUP}
                                export CUDA_VISIBLE_DEVICES=0
                                pushd install-${name}/test
                                ${TEST_ROTATE}
                                nice -n 10 ./test.com ${cfg.test_args} output old/output &> test.log
                                popd
                            """
                            echo "...finished testing ${name}"
                        }
                    }

                    // CPU tests — run in batches
                    def cpuTestJobs = [:]
                    charmmConfigs.findAll { name, cfg ->
                        cfg.test != false && cfg.test_args && !cfg.gpus
                    }.each { name, cfg ->
                        def sccdftbSetup = (name == 'sccdftb') ? SCCDFTB_SETUP : ""
                        cpuTestJobs["Test ${name}"] = {
                            stage("Test ${name}") {
                                echo "Testing ${name}..."
                                sh """
                                    ${ENV_SETUP}
                                    pushd install-${name}/test
                                    ${TEST_ROTATE}
                                    ${sccdftbSetup}
                                    nice -n 10 ./test.com ${cfg.test_args} output old/output &> test.log
                                    popd
                                """
                                echo "...finished testing ${name}"
                            }
                        }
                    }
                    runInBatches(cpuTestJobs, MAX_TEST_CONCURRENT)
                }
            }
        }
        stage("Pytest pyCHARMM") {
            steps {
                script {
                    charmmConfigs.findAll { name, cfg -> cfg.pytest }.each { name, cfg ->
                        echo "Running pyCHARMM pytest suite against install-${name}..."
                        // Don't let pytest crashes kill the stage — we want
                        // the junit step to run either way so we see what
                        // happened. Capture the exit code for diagnostics.
                        def rc = sh(returnStatus: true, script: """
                            ${ENV_SETUP}
                            pushd install-${name}
                            export CHARMM_DATA_DIR=\$(pwd)/toppar
                            # Pin the suite to THIS config's libchmm.  Every
                            # config pip-installs pycharmm into the one shared
                            # conda env, and loader.py has its library dir
                            # substituted in by configure_file() at install
                            # time -- so site-packages points at whichever
                            # build ran `ninja install` last, across
                            # pipeline-dev and pipeline-stable both.  Without
                            # this the tests silently exercise some other
                            # build: seen as test_mpi_usable_native_repdstr_
                            # lifecycle failing with "REPlica DiSTRibuted code
                            # not compiled" on install-gpu, which is built
                            # --with-repdstr.  The constructor argument wins
                            # over the baked-in default, and mpirun ranks
                            # inherit it through the environment.
                            export CHARMM_LIB_DIR=\$(pwd)/lib
                            cd tool/pycharmm
                            # Use an absolute path for --junitxml so the
                            # result lands in cwd regardless of where
                            # pytest resolves its rootdir.  With a bare
                            # filename + ``pytest tests/``, pytest puts
                            # the XML under tests/, off-by-one from
                            # where the post-step fileExists() looks.
                            xml_path=\$(pwd)/pytest-results.xml
                            rm -f "\$xml_path"
                            set +e
                            PYTHONFAULTHANDLER=1 nice -n 10 pytest -v --tb=short --junitxml="\$xml_path" tests/ 2>&1 | tee pytest.log
                            pytest_rc=\${PIPESTATUS[0]}
                            echo ""
                            echo "pytest exit code: \$pytest_rc"
                            ls -la "\$xml_path" 2>/dev/null || echo "WARNING: pytest-results.xml was not written (pytest likely crashed)"
                            popd
                            exit \$pytest_rc
                        """)
                        echo "pytest returned ${rc}"
                        // Publish XML if it exists; don't fail the stage if not
                        if (fileExists("install-${name}/tool/pycharmm/pytest-results.xml")) {
                            junit allowEmptyResults: true,
                                  skipOldReports: true,
                                  testResults: "install-${name}/tool/pycharmm/pytest-results.xml"
                        } else {
                            unstable("pytest for ${name} did not produce pytest-results.xml")
                        }
                        echo "...finished pyCHARMM pytest (${name})"
                    }
                }
            }
        }
        stage("Report") {
            steps {
                script {
                    def testableNames = charmmConfigs.findAll { name, cfg ->
                        cfg.test != false && cfg.test_args
                    }.keySet().join(' ')
                    echo "Grading test results..."
                    sh """
                        ${ENV_SETUP}
                        rm -f test-results.xml
                        export CHARMM_TEST_HOME=\${WORKSPACE}
                        python \${WORKSPACE}/testing/charmm-test grade \
                            --tol 0.0001 --xml test-results.xml \
                            ${testableNames}
                    """
                    junit allowEmptyResults: true,
                          skipOldReports: true,
                          testResults: 'test-results.xml'
                    echo "...finished grading"
                }
            }
        }
    }
    post {
        always {
            archiveArtifacts artifacts: 'install-*/test/*.log,install-*/test/*.xml,install-*/tool/pycharmm/pytest*',
                             allowEmptyArchive: true
        }
        failure {
            echo 'Pipeline failed — check archived test logs for details'
        }
    }
}
