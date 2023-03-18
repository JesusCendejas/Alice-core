
from setuptools import setup, find_packages
import os
import os.path

BASEDIR = os.path.abspath(os.path.dirname(__file__))


def get_version():
    """ Find the version of alice-core"""
    version = None
    version_file = os.path.join(BASEDIR, 'alice', 'version', '__init__.py')
    major, minor, build = (None, None, None)
    with open(version_file) as f:
        for line in f:
            if 'CORE_VERSION_MAJOR' in line:
                major = line.split('=')[1].strip()
            elif 'CORE_VERSION_MINOR' in line:
                minor = line.split('=')[1].strip()
            elif 'CORE_VERSION_BUILD' in line:
                build = line.split('=')[1].strip()

            if ((major and minor and build) or
                    '# END_VERSION_BLOCK' in line):
                break
    version = '.'.join([major, minor, build])

    return version


def required(requirements_file):
    """ Read requirements file and remove comments and empty lines. """
    with open(os.path.join(BASEDIR, requirements_file), 'r') as f:
        requirements = f.read().splitlines()
        if 'ALICE_LOOSE_REQUIREMENTS' in os.environ:
            print('USING LOOSE REQUIREMENTS!')
            requirements = [r.replace('==', '>=') for r in requirements]
        return [pkg for pkg in requirements
                if pkg.strip() and not pkg.startswith("#")]


setup(
    name='alice-core',
    version=get_version(),
    license='Apache-2.0',
    author='Alice-IA',
    author_email='devs@mycroft.ai',
    url='https://github.com/Alice-IA/Alice-core.git',
    description='Alice Core',
    install_requires=required('requirements/requirements.txt'),
    extras_require={
        'audio-backend': required('requirements/extra-audiobackend.txt'),
        'mark1': required('requirements/extra-mark1.txt'),
        'stt': required('requirements/extra-stt.txt')
    },
    packages=find_packages(include=['alice*']),
    include_package_data=True,

    entry_points={
        'console_scripts': [
            'alice-speech-client=alice.client.speech.__main__:main',
            'alice-messagebus=alice.messagebus.service.__main__:main',
            'alice-skills=alice.skills.__main__:main',
            'alice-audio=alice.audio.__main__:main',
            'alice-echo-observer=alice.messagebus.client.ws:echo',
            'alice-audio-test=alice.util.audio_test:main',
            'alice-enclosure-client=alice.client.enclosure.__main__:main',
            'alice-cli-client=alice.client.text.__main__:main'
        ]
    }
)
